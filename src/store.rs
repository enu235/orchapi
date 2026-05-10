use crate::outcome::Outcome;
use anyhow::Result;
use chrono::Utc;
use sqlx::{sqlite::SqliteConnectOptions, SqlitePool};
use std::path::Path;
use std::str::FromStr;

pub async fn create_pool(data_dir: &Path) -> Result<SqlitePool> {
    let db_path = data_dir.join("orchapi.db");
    let options = SqliteConnectOptions::from_str(&format!("sqlite:{}", db_path.display()))?
        .create_if_missing(true);
    let pool = SqlitePool::connect_with(options).await?;
    Ok(pool)
}

pub async fn run_migrations(pool: &SqlitePool) -> Result<()> {
    let sql_init = include_str!("../migrations/0001_init.sql");
    for stmt in sql_init.split(';') {
        let stmt = stmt.trim();
        if !stmt.is_empty() {
            sqlx::query(stmt).execute(pool).await?;
        }
    }
    let sql_ext = include_str!("../migrations/0002_external_task.sql");
    for stmt in sql_ext.split(';') {
        let stmt = stmt.trim();
        if stmt.is_empty() {
            continue;
        }
        if let Err(e) = sqlx::query(stmt).execute(pool).await {
            let msg = e.to_string().to_lowercase();
            if msg.contains("duplicate column") || msg.contains("already exists") {
                continue;
            }
            return Err(e.into());
        }
    }
    Ok(())
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct SessionRow {
    pub id: String,
    pub agent: String,
    pub profile: Option<String>,
    pub spec_json: String,
    pub status: String,
    pub queued_at: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub exit_code: Option<i64>,
    pub outcome_summary: Option<String>,
    pub usage_json: Option<String>,
    pub log_path: String,
    pub parent_session: Option<String>,
    pub tags_json: Option<String>,
    pub external_task_json: Option<String>,
    pub writeback_status: Option<String>,
    pub writeback_attempts: i64,
    pub writeback_last_error: Option<String>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct SessionEventRow {
    pub id: i64,
    pub session_id: String,
    pub ts: String,
    pub kind: String,
    pub payload: Option<String>,
}

pub async fn insert_session(
    pool: &SqlitePool,
    id: &str,
    agent: &str,
    profile: Option<&str>,
    spec_json: &str,
    log_path: &str,
    parent_session: Option<&str>,
    tags: &[String],
    external_task_json: Option<&str>,
) -> Result<()> {
    let queued_at = Utc::now().to_rfc3339();
    let tags_json = if tags.is_empty() {
        None
    } else {
        Some(serde_json::to_string(tags)?)
    };
    let writeback_status: Option<&str> = if external_task_json.is_some() {
        Some("pending")
    } else {
        None
    };
    sqlx::query(
        "INSERT INTO sessions (id, agent, profile, spec_json, status, queued_at, log_path, parent_session, tags_json, external_task_json, writeback_status)
         VALUES (?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?)"
    )
    .bind(id)
    .bind(agent)
    .bind(profile)
    .bind(spec_json)
    .bind(&queued_at)
    .bind(log_path)
    .bind(parent_session)
    .bind(tags_json.as_deref())
    .bind(external_task_json)
    .bind(writeback_status)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn set_running(pool: &SqlitePool, id: &str) -> Result<()> {
    let now = Utc::now().to_rfc3339();
    sqlx::query("UPDATE sessions SET status='running', started_at=? WHERE id=?")
        .bind(&now)
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn set_finished(pool: &SqlitePool, id: &str, outcome: &Outcome) -> Result<()> {
    let now = Utc::now().to_rfc3339();
    let status = outcome.kind.to_string();
    let usage_json = outcome
        .usage
        .as_ref()
        .map(|u| serde_json::to_string(u))
        .transpose()?;
    sqlx::query(
        "UPDATE sessions SET status=?, finished_at=?, exit_code=?, outcome_summary=?, usage_json=? WHERE id=?"
    )
    .bind(&status)
    .bind(&now)
    .bind(outcome.exit_code)
    .bind(outcome.summary.as_deref())
    .bind(usage_json.as_deref())
    .bind(id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_session(pool: &SqlitePool, id: &str) -> Result<Option<SessionRow>> {
    let row = sqlx::query_as::<_, SessionRow>("SELECT * FROM sessions WHERE id=?")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}

pub async fn list_sessions(
    pool: &SqlitePool,
    status: Option<&str>,
    agent: Option<&str>,
    profile: Option<&str>,
    limit: i64,
    since: Option<&str>,
    writeback_status: Option<&str>,
) -> Result<Vec<SessionRow>> {
    let mut q = String::from("SELECT * FROM sessions WHERE 1=1");
    if status.is_some() {
        q.push_str(" AND status=?");
    }
    if agent.is_some() {
        q.push_str(" AND agent=?");
    }
    if profile.is_some() {
        q.push_str(" AND profile=?");
    }
    if since.is_some() {
        q.push_str(" AND queued_at >= ?");
    }
    if writeback_status.is_some() {
        q.push_str(" AND writeback_status=?");
    }
    q.push_str(" ORDER BY queued_at DESC LIMIT ?");

    let mut query = sqlx::query_as::<_, SessionRow>(&q);
    if let Some(s) = status {
        query = query.bind(s);
    }
    if let Some(a) = agent {
        query = query.bind(a);
    }
    if let Some(p) = profile {
        query = query.bind(p);
    }
    if let Some(si) = since {
        query = query.bind(si);
    }
    if let Some(ws) = writeback_status {
        query = query.bind(ws);
    }
    query = query.bind(limit);

    let rows = query.fetch_all(pool).await?;
    Ok(rows)
}

pub async fn claim_writeback(pool: &SqlitePool, id: &str) -> Result<bool> {
    let r = sqlx::query(
        "UPDATE sessions SET writeback_status='in_progress', writeback_attempts=writeback_attempts+1
         WHERE id=? AND writeback_status='pending'",
    )
    .bind(id)
    .execute(pool)
    .await?;
    Ok(r.rows_affected() == 1)
}

pub async fn ack_writeback(
    pool: &SqlitePool,
    id: &str,
    result: &str,
    error: Option<&str>,
    refreshed_etag_json: Option<&str>,
) -> Result<()> {
    sqlx::query(
        "UPDATE sessions SET writeback_status=?, writeback_last_error=?,
         external_task_json=COALESCE(?, external_task_json) WHERE id=?",
    )
    .bind(result)
    .bind(error)
    .bind(refreshed_etag_json)
    .bind(id)
    .execute(pool)
    .await?;
    Ok(())
}

#[allow(dead_code)]
pub async fn list_pending_writeback(pool: &SqlitePool, limit: i64) -> Result<Vec<SessionRow>> {
    let rows = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE writeback_status='pending' ORDER BY queued_at ASC LIMIT ?",
    )
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn insert_session_event(
    pool: &SqlitePool,
    session_id: &str,
    kind: &str,
    payload: Option<&str>,
) -> Result<()> {
    let ts = Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO session_events (session_id, ts, kind, payload) VALUES (?, ?, ?, ?)",
    )
    .bind(session_id)
    .bind(&ts)
    .bind(kind)
    .bind(payload)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_session_events(
    pool: &SqlitePool,
    session_id: &str,
) -> Result<Vec<SessionEventRow>> {
    let rows = sqlx::query_as::<_, SessionEventRow>(
        "SELECT id, session_id, ts, kind, payload FROM session_events WHERE session_id=? ORDER BY id ASC",
    )
    .bind(session_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn count_by_status(pool: &SqlitePool) -> Result<serde_json::Value> {
    let rows: Vec<(String, i64)> =
        sqlx::query_as("SELECT status, COUNT(*) FROM sessions GROUP BY status")
            .fetch_all(pool)
            .await?;
    let mut map = serde_json::Map::new();
    for (status, count) in rows {
        map.insert(status, serde_json::Value::Number(count.into()));
    }
    Ok(serde_json::Value::Object(map))
}

pub async fn mark_running_as_cancelled(pool: &SqlitePool, reason: &str) -> Result<u64> {
    let now = Utc::now().to_rfc3339();
    let r = sqlx::query(
        "UPDATE sessions SET status='cancelled', finished_at=?, outcome_summary=? WHERE status IN ('running','queued')"
    )
    .bind(&now)
    .bind(reason)
    .execute(pool)
    .await?;
    Ok(r.rows_affected())
}
