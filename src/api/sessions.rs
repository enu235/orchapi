use crate::spec::{resolve_spec, AgentKind, SessionSpecPartial};
use crate::store;
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response, Sse};
use axum::Json;
use futures::stream::{self};
use serde::{Deserialize, Serialize};
use std::convert::Infallible;
use std::str::FromStr;
use std::sync::Arc;
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::StreamExt as _;
use uuid::Uuid;

use crate::AppState;

#[derive(Deserialize)]
pub struct CreateSessionRequest {
    pub agent: String,
    pub profile: Option<String>,
    #[serde(default)]
    pub overrides: SessionSpecPartial,
    // top-level convenience fields that shadow overrides
    pub parent_session: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Serialize)]
pub struct CreateSessionResponse {
    pub id: String,
    pub status: &'static str,
}

pub async fn create_session(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CreateSessionRequest>,
) -> impl IntoResponse {
    let agent = match AgentKind::from_str(&req.agent) {
        Ok(a) => a,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": e.to_string()})),
            )
                .into_response()
        }
    };

    let profile_store = state.profiles.read().await;
    let profile = req
        .profile
        .as_deref()
        .and_then(|n| profile_store.get(n));

    let mut overrides = req.overrides;
    // parent_session and tags at top level flow into overrides if not already set
    if req.parent_session.is_some() && overrides.parent_session.is_none() {
        overrides.parent_session = req.parent_session.clone();
    }
    if !req.tags.is_empty() && overrides.tags.is_empty() {
        overrides.tags = req.tags.clone();
    }

    let spec = match resolve_spec(agent, profile, &overrides, &state.config) {
        Ok(s) => s,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": e.to_string()})),
            )
                .into_response()
        }
    };

    let session_id = Uuid::now_v7().to_string();
    let tags = overrides.tags.clone();
    let parent = overrides.parent_session.clone();

    if let Err(e) = state
        .manager
        .spawn_session(
            session_id.clone(),
            spec,
            req.profile.clone(),
            parent,
            tags,
        )
        .await
    {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response();
    }

    (
        StatusCode::CREATED,
        Json(CreateSessionResponse {
            id: session_id,
            status: "queued",
        }),
    )
        .into_response()
}

#[derive(Deserialize, Default)]
pub struct ListQuery {
    pub status: Option<String>,
    pub agent: Option<String>,
    pub profile: Option<String>,
    pub limit: Option<i64>,
    pub since: Option<String>,
    pub writeback_status: Option<String>,
}

pub async fn list_sessions(
    State(state): State<Arc<AppState>>,
    Query(q): Query<ListQuery>,
) -> impl IntoResponse {
    let limit = q.limit.unwrap_or(50).min(500);
    match store::list_sessions(
        state.manager.pool(),
        q.status.as_deref(),
        q.agent.as_deref(),
        q.profile.as_deref(),
        limit,
        q.since.as_deref(),
        q.writeback_status.as_deref(),
    )
    .await
    {
        Ok(rows) => Json(rows_to_json(rows)).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

pub async fn get_session(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match store::get_session(state.manager.pool(), &id).await {
        Ok(Some(row)) => Json(row_to_json(row)).into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "not found"})),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

pub async fn get_logs(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let row = match store::get_session(state.manager.pool(), &id).await {
        Ok(Some(r)) => r,
        Ok(None) => return (StatusCode::NOT_FOUND, "not found").into_response(),
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };
    match tokio::fs::read_to_string(&row.log_path).await {
        Ok(content) => Response::builder()
            .header("content-type", "text/plain; charset=utf-8")
            .body(Body::from(content))
            .unwrap()
            .into_response(),
        Err(_) => (StatusCode::NOT_FOUND, "log file not found").into_response(),
    }
}

pub async fn stream_session(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    // Try to subscribe to a live broadcast first
    if let Some(rx) = state.manager.subscribe(&id).await {
        let stream = BroadcastStream::new(rx).filter_map(|result| {
            result.ok().map(|line| {
                let event_type = match line.stream {
                    crate::log_writer::Stream::Stdout => "stdout",
                    crate::log_writer::Stream::Stderr => "stderr",
                };
                Ok::<_, Infallible>(
                    axum::response::sse::Event::default()
                        .event(event_type)
                        .data(line.text),
                )
            })
        });
        return Sse::new(stream)
            .keep_alive(axum::response::sse::KeepAlive::default())
            .into_response();
    }

    // Session is done — stream the log file as a series of SSE events
    let row = match store::get_session(state.manager.pool(), &id).await {
        Ok(Some(r)) => r,
        Ok(None) => return (StatusCode::NOT_FOUND, "not found").into_response(),
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    };

    let content = tokio::fs::read_to_string(&row.log_path)
        .await
        .unwrap_or_default();

    let events: Vec<Result<axum::response::sse::Event, Infallible>> = content
        .lines()
        .map(|line| {
            let (event_type, text) = if let Some(t) = line.strip_prefix("[OUT] ") {
                ("stdout", t)
            } else if let Some(t) = line.strip_prefix("[ERR] ") {
                ("stderr", t)
            } else {
                ("stdout", line)
            };
            Ok(axum::response::sse::Event::default()
                .event(event_type)
                .data(text.to_string()))
        })
        .collect();

    let done_event = Ok(axum::response::sse::Event::default()
        .event("outcome")
        .data(row.status.clone()));
    let all_events = events
        .into_iter()
        .chain(std::iter::once(done_event))
        .collect::<Vec<_>>();

    let st = stream::iter(all_events);
    Sse::new(st)
        .keep_alive(axum::response::sse::KeepAlive::default())
        .into_response()
}

pub async fn cancel_session(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match state.manager.cancel(&id).await {
        Ok(true) => Json(serde_json::json!({"ok": true})).into_response(),
        Ok(false) => (
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "session not cancellable"})),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

fn row_to_json(row: crate::store::SessionRow) -> serde_json::Value {
    serde_json::json!({
        "id": row.id,
        "agent": row.agent,
        "profile": row.profile,
        "status": row.status,
        "queued_at": row.queued_at,
        "started_at": row.started_at,
        "finished_at": row.finished_at,
        "exit_code": row.exit_code,
        "outcome_summary": row.outcome_summary,
        "usage": row.usage_json.and_then(|u| serde_json::from_str::<serde_json::Value>(&u).ok()),
        "log_path": row.log_path,
        "parent_session": row.parent_session,
        "tags": row.tags_json.and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok()),
        "spec": serde_json::from_str::<serde_json::Value>(&row.spec_json).ok(),
        "external_task": row.external_task_json.and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok()),
        "writeback_status": row.writeback_status,
        "writeback_attempts": row.writeback_attempts,
        "writeback_last_error": row.writeback_last_error,
    })
}

fn rows_to_json(rows: Vec<crate::store::SessionRow>) -> serde_json::Value {
    serde_json::Value::Array(rows.into_iter().map(row_to_json).collect())
}

#[derive(Deserialize)]
pub struct PostEventRequest {
    pub kind: String,
    pub text: Option<String>,
    pub percent_complete: Option<i32>,
}

pub async fn post_session_event(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Json(req): Json<PostEventRequest>,
) -> impl IntoResponse {
    let mut payload = serde_json::Map::new();
    if let Some(t) = req.text {
        payload.insert("text".to_string(), serde_json::Value::String(t));
    }
    if let Some(p) = req.percent_complete {
        payload.insert(
            "percent_complete".to_string(),
            serde_json::Value::Number(p.into()),
        );
    }
    let payload_str = if payload.is_empty() {
        None
    } else {
        Some(serde_json::Value::Object(payload).to_string())
    };
    match store::insert_session_event(
        state.manager.pool(),
        &id,
        &req.kind,
        payload_str.as_deref(),
    )
    .await
    {
        Ok(()) => (
            StatusCode::ACCEPTED,
            Json(serde_json::json!({"ok": true})),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

pub async fn get_session_events(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match store::list_session_events(state.manager.pool(), &id).await {
        Ok(rows) => {
            let arr: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|r| {
                    serde_json::json!({
                        "id": r.id,
                        "session_id": r.session_id,
                        "ts": r.ts,
                        "kind": r.kind,
                        "payload": r.payload.and_then(|p| serde_json::from_str::<serde_json::Value>(&p).ok()),
                    })
                })
                .collect();
            Json(serde_json::Value::Array(arr)).into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

pub async fn claim_writeback(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match store::claim_writeback(state.manager.pool(), &id).await {
        Ok(true) => (StatusCode::OK, Json(serde_json::json!({"ok": true}))).into_response(),
        Ok(false) => (
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "not pending"})),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}

#[derive(Deserialize)]
pub struct AckWritebackRequest {
    pub result: String,
    pub error: Option<String>,
    pub refreshed_etags: Option<serde_json::Value>,
}

pub async fn ack_writeback(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Json(req): Json<AckWritebackRequest>,
) -> impl IntoResponse {
    let refreshed = req.refreshed_etags.as_ref().map(|v| v.to_string());
    match store::ack_writeback(
        state.manager.pool(),
        &id,
        &req.result,
        req.error.as_deref(),
        refreshed.as_deref(),
    )
    .await
    {
        Ok(()) => (StatusCode::OK, Json(serde_json::json!({"ok": true}))).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": e.to_string()})),
        )
            .into_response(),
    }
}
