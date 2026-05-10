use crate::adapters::adapter_for;
use crate::config::AppConfig;
use crate::log_writer::{session_log_path, LogWriter, Stream};
use crate::outcome::Outcome;
use crate::spec::{AgentKind, ExternalTaskRef, SessionSpec};
use crate::store;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::{broadcast, Mutex, Semaphore};
use tracing::{error, info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WritebackSignal {
    pub session_id: String,
    pub status: String,
    pub external_task: Option<ExternalTaskRef>,
}

pub struct SessionManager {
    pool: SqlitePool,
    data_dir: PathBuf,
    global_sem: Arc<Semaphore>,
    claude_sem: Arc<Semaphore>,
    copilot_sem: Arc<Semaphore>,
    codex_sem: Arc<Semaphore>,
    // session_id -> broadcast sender for SSE
    pub live: Arc<Mutex<HashMap<String, broadcast::Sender<LogLine>>>>,
    pub writeback_tx: broadcast::Sender<WritebackSignal>,
    #[allow(dead_code)]
    cancel_grace: u64,
}

pub use crate::log_writer::LogLine;

impl SessionManager {
    pub fn new(
        pool: SqlitePool,
        config: &AppConfig,
        writeback_tx: broadcast::Sender<WritebackSignal>,
    ) -> Self {
        let c = config.concurrency.normalized();
        let cancel_grace = config.defaults.cancel_grace_seconds.unwrap_or(10);
        Self {
            pool,
            data_dir: config.server.data_dir.clone(),
            global_sem: Arc::new(Semaphore::new(c.global)),
            claude_sem: Arc::new(Semaphore::new(c.claude)),
            copilot_sem: Arc::new(Semaphore::new(c.copilot)),
            codex_sem: Arc::new(Semaphore::new(c.codex)),
            live: Arc::new(Mutex::new(HashMap::new())),
            writeback_tx,
            cancel_grace,
        }
    }

    fn agent_sem(&self, kind: &AgentKind) -> Arc<Semaphore> {
        match kind {
            AgentKind::Claude => self.claude_sem.clone(),
            AgentKind::Copilot => self.copilot_sem.clone(),
            AgentKind::Codex => self.codex_sem.clone(),
        }
    }

    pub async fn spawn_session(
        self: &Arc<Self>,
        session_id: String,
        spec: SessionSpec,
        profile_name: Option<String>,
        parent_session: Option<String>,
        tags: Vec<String>,
    ) -> Result<()> {
        let log_path = session_log_path(&self.data_dir, &session_id);
        let log_path_str = log_path.to_string_lossy().to_string();
        let spec_json = serde_json::to_string(&spec)?;
        let external_task_json = spec
            .external_task
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;

        store::insert_session(
            &self.pool,
            &session_id,
            &spec.agent.to_string(),
            profile_name.as_deref(),
            &spec_json,
            &log_path_str,
            parent_session.as_deref(),
            &tags,
            external_task_json.as_deref(),
        )
        .await?;

        let manager = self.clone();
        tokio::spawn(async move {
            if let Err(e) = manager.run_session(session_id.clone(), spec, log_path).await {
                error!("session {session_id} error: {e:#}");
            }
        });

        Ok(())
    }

    async fn run_session(
        self: &Arc<Self>,
        session_id: String,
        spec: SessionSpec,
        log_path: PathBuf,
    ) -> Result<()> {
        let global_permit = self.global_sem.clone().acquire_owned().await?;
        let agent_permit = self.agent_sem(&spec.agent).clone().acquire_owned().await?;

        let log_writer = LogWriter::create(&log_path).await?;
        // Register the broadcast sender so SSE subscribers can tap in
        {
            let mut live = self.live.lock().await;
            live.insert(session_id.clone(), log_writer.tx.clone());
        }

        store::set_running(&self.pool, &session_id).await?;
        info!("session {session_id} started (agent={})", spec.agent);

        let adapter = adapter_for(&spec.agent);
        let mut cmd = adapter.build_command(&spec)?;
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());
        cmd.kill_on_drop(true);

        let mut child: Child = cmd.spawn()?;

        let stdout = child.stdout.take().unwrap();
        let stderr = child.stderr.take().unwrap();

        let sid = session_id.clone();
        let tx_out = log_writer.tx.clone();

        // Stdout reader task — shares the broadcast sender from the primary log writer
        let lw_stdout = {
            let mut lw = LogWriter::create(&log_path).await?;
            lw.tx = tx_out.clone();
            lw
        };
        let mut lw_out = lw_stdout;

        let stdout_task = {
            let sid2 = sid.clone();
            tokio::spawn(async move {
                let mut reader = BufReader::new(stdout).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    if let Err(e) = lw_out.write(Stream::Stdout, &line).await {
                        warn!("session {sid2} stdout write error: {e}");
                    }
                }
            })
        };

        // Stderr reader task — shares the same log file via the broadcast channel trick;
        // we open a second writer to the same file (append mode) for stderr.
        let stderr_lp = log_path.clone();
        let tx_err = log_writer.tx.clone();
        let stderr_task = {
            let sid2 = sid.clone();
            tokio::spawn(async move {
                let lw_result = LogWriter::create(&stderr_lp).await;
                let mut lw_err = match lw_result {
                    Ok(mut lw) => {
                        lw.tx = tx_err;
                        lw
                    }
                    Err(e) => {
                        warn!("session {sid2} could not open err log: {e}");
                        return;
                    }
                };
                let mut reader = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    if let Err(e) = lw_err.write(Stream::Stderr, &line).await {
                        warn!("session {sid2} stderr write error: {e}");
                    }
                }
            })
        };

        let status = child.wait().await?;
        let exit_code = status.code().unwrap_or(-1);

        stdout_task.await.ok();
        stderr_task.await.ok();

        // Read the full log for outcome extraction
        let log_text = tokio::fs::read_to_string(&log_path).await.unwrap_or_default();
        let mut outcome = adapter.extract_outcome(&log_text, exit_code);
        // strip log prefixes for cleaner summary
        let clean_log = log_text
            .lines()
            .map(|l| {
                l.strip_prefix("[OUT] ")
                    .or_else(|| l.strip_prefix("[ERR] "))
                    .unwrap_or(l)
            })
            .collect::<Vec<_>>()
            .join("\n");
        if outcome.summary.is_none() {
            outcome = adapter.extract_outcome(&clean_log, exit_code);
        }

        store::set_finished(&self.pool, &session_id, &outcome).await?;

        info!(
            "session {session_id} finished: {:?} exit={exit_code}",
            outcome.kind
        );

        if spec.external_task.is_some() {
            let status = outcome.kind.to_string();
            let payload = serde_json::json!({
                "status": status,
                "exit_code": exit_code,
                "summary": outcome.summary,
            })
            .to_string();
            if let Err(e) =
                store::insert_session_event(&self.pool, &session_id, "terminal", Some(&payload))
                    .await
            {
                warn!("session {session_id} failed to insert terminal event: {e}");
            }
            let _ = self.writeback_tx.send(WritebackSignal {
                session_id: session_id.clone(),
                status,
                external_task: spec.external_task.clone(),
            });
        }

        // Deregister from live map
        {
            let mut live = self.live.lock().await;
            live.remove(&session_id);
        }

        drop(global_permit);
        drop(agent_permit);
        drop(log_writer);

        Ok(())
    }

    /// Returns a broadcast receiver if the session is currently running.
    pub async fn subscribe(&self, session_id: &str) -> Option<broadcast::Receiver<LogLine>> {
        let live = self.live.lock().await;
        live.get(session_id).map(|tx| tx.subscribe())
    }

    /// Cancels a running session by its OS PID recorded in the process group.
    /// This is a best-effort SIGTERM then SIGKILL after grace period.
    /// Since we store no PID, we rely on kill_on_drop (via Child) already installed.
    /// A more robust cancel path requires storing the Child handle; this is a v1 approximation.
    pub async fn cancel(&self, session_id: &str) -> Result<bool> {
        let row = store::get_session(&self.pool, session_id).await?;
        let Some(row) = row else { return Ok(false) };
        if row.status != "running" && row.status != "queued" {
            return Ok(false);
        }
        let outcome = Outcome::cancelled("user requested cancellation");
        store::set_finished(&self.pool, session_id, &outcome).await?;

        let spec_external = serde_json::from_str::<SessionSpec>(&row.spec_json)
            .ok()
            .and_then(|s| s.external_task);
        if let Some(et) = spec_external {
            let status = outcome.kind.to_string();
            let payload = serde_json::json!({
                "status": status,
                "summary": outcome.summary,
            })
            .to_string();
            if let Err(e) =
                store::insert_session_event(&self.pool, session_id, "terminal", Some(&payload))
                    .await
            {
                warn!("session {session_id} failed to insert terminal event: {e}");
            }
            let _ = self.writeback_tx.send(WritebackSignal {
                session_id: session_id.to_string(),
                status,
                external_task: Some(et),
            });
        }
        Ok(true)
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }
}
