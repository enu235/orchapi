use crate::outcome::Outcome;
use crate::spec::{AgentKind, SessionSpec};
use anyhow::Result;
use tokio::process::Command;

mod claude;
mod codex;
mod copilot;

pub use claude::ClaudeAdapter;
pub use codex::CodexAdapter;
pub use copilot::CopilotAdapter;

pub trait AgentAdapter: Send + Sync {
    #[allow(dead_code)]
    fn kind(&self) -> AgentKind;
    fn build_command(&self, spec: &SessionSpec) -> Result<Command>;
    fn extract_outcome(&self, log: &str, exit_code: i32) -> Outcome;
}

pub fn adapter_for(kind: &AgentKind) -> Box<dyn AgentAdapter> {
    match kind {
        AgentKind::Claude => Box::new(ClaudeAdapter),
        AgentKind::Copilot => Box::new(CopilotAdapter),
        AgentKind::Codex => Box::new(CodexAdapter),
    }
}
