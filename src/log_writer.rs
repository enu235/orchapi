use anyhow::Result;
use std::path::{Path, PathBuf};
use tokio::fs::{self, File, OpenOptions};
use tokio::io::AsyncWriteExt;
use tokio::sync::broadcast;

const BROADCAST_CAPACITY: usize = 512;

/// A per-session fanout writer: appends to a log file and broadcasts to SSE subscribers.
pub struct LogWriter {
    pub tx: broadcast::Sender<LogLine>,
    #[allow(dead_code)]
    log_path: PathBuf,
    file: File,
}

#[derive(Debug, Clone)]
pub struct LogLine {
    pub stream: Stream,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Stream {
    Stdout,
    Stderr,
}

impl LogWriter {
    pub async fn create(log_path: &Path) -> Result<Self> {
        if let Some(parent) = log_path.parent() {
            fs::create_dir_all(parent).await?;
        }
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_path)
            .await?;
        let (tx, _) = broadcast::channel(BROADCAST_CAPACITY);
        Ok(Self {
            tx,
            log_path: log_path.to_path_buf(),
            file,
        })
    }

    pub async fn write(&mut self, stream: Stream, text: &str) -> Result<()> {
        let prefix = match stream {
            Stream::Stdout => "[OUT]",
            Stream::Stderr => "[ERR]",
        };
        let line = format!("{prefix} {text}\n");
        self.file.write_all(line.as_bytes()).await?;
        // Broadcast — ignore if no subscribers
        let _ = self.tx.send(LogLine {
            stream,
            text: text.to_string(),
        });
        Ok(())
    }

    #[allow(dead_code)]
    pub fn subscribe(&self) -> broadcast::Receiver<LogLine> {
        self.tx.subscribe()
    }

    #[allow(dead_code)]
    pub fn log_path(&self) -> &Path {
        &self.log_path
    }
}

pub fn session_log_path(data_dir: &Path, session_id: &str) -> PathBuf {
    let now = chrono::Utc::now();
    data_dir
        .join("logs")
        .join(now.format("%Y").to_string())
        .join(now.format("%m").to_string())
        .join(now.format("%d").to_string())
        .join(format!("{session_id}.log"))
}
