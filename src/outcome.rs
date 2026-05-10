use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OutcomeKind {
    Success,
    Failed,
    Cancelled,
    Timeout,
}

impl std::fmt::Display for OutcomeKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Success => write!(f, "success"),
            Self::Failed => write!(f, "failed"),
            Self::Cancelled => write!(f, "cancelled"),
            Self::Timeout => write!(f, "timeout"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Outcome {
    pub kind: OutcomeKind,
    pub exit_code: Option<i32>,
    pub summary: Option<String>,
    pub usage: Option<serde_json::Value>,
}

impl Outcome {
    #[allow(dead_code)]
    pub fn from_exit(code: i32) -> Self {
        Self {
            kind: if code == 0 {
                OutcomeKind::Success
            } else {
                OutcomeKind::Failed
            },
            exit_code: Some(code),
            summary: None,
            usage: None,
        }
    }

    pub fn cancelled(reason: &str) -> Self {
        Self {
            kind: OutcomeKind::Cancelled,
            exit_code: None,
            summary: Some(reason.to_string()),
            usage: None,
        }
    }
}

/// Extracts the last assistant text block from a Claude Code stream-json log.
pub fn extract_claude_outcome(log: &str, exit_code: i32) -> Outcome {
    let mut summary: Option<String> = None;
    let mut usage: Option<serde_json::Value> = None;

    for line in log.lines() {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        match v.get("type").and_then(|t| t.as_str()) {
            Some("result") => {
                if let Some(text) = v.get("result").and_then(|r| r.as_str()) {
                    let truncated = text.chars().take(300).collect::<String>();
                    summary = Some(truncated);
                }
                if let Some(u) = v.get("usage") {
                    usage = Some(u.clone());
                }
            }
            Some("assistant") => {
                if let Some(content) = v
                    .get("message")
                    .and_then(|m| m.get("content"))
                    .and_then(|c| c.as_array())
                {
                    for block in content {
                        if block.get("type").and_then(|t| t.as_str()) == Some("text") {
                            if let Some(text) = block.get("text").and_then(|t| t.as_str()) {
                                let truncated = text.chars().take(300).collect::<String>();
                                summary = Some(truncated);
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    }

    Outcome {
        kind: if exit_code == 0 {
            OutcomeKind::Success
        } else {
            OutcomeKind::Failed
        },
        exit_code: Some(exit_code),
        summary,
        usage,
    }
}

/// Extracts a short summary from the tail of a text log (used for Codex and Copilot).
pub fn extract_text_outcome(log: &str, exit_code: i32) -> Outcome {
    let summary = log
        .lines()
        .rev()
        .find(|l| !l.trim().is_empty())
        .map(|l| l.chars().take(300).collect::<String>());

    Outcome {
        kind: if exit_code == 0 {
            OutcomeKind::Success
        } else {
            OutcomeKind::Failed
        },
        exit_code: Some(exit_code),
        summary,
        usage: None,
    }
}
