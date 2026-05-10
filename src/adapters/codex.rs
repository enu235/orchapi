use crate::adapters::AgentAdapter;
use crate::outcome::{extract_text_outcome, Outcome};
use crate::spec::{AgentKind, SessionSpec};
use anyhow::Result;
use tokio::process::Command;

pub struct CodexAdapter;

impl AgentAdapter for CodexAdapter {
    fn kind(&self) -> AgentKind {
        AgentKind::Codex
    }

    fn build_command(&self, spec: &SessionSpec) -> Result<Command> {
        let mut cmd = Command::new("codex");
        cmd.current_dir(&spec.cwd);
        cmd.envs(&spec.env);

        cmd.arg("exec");

        if let Some(model) = &spec.model {
            cmd.args(["-m", model]);
        }
        if let Some(sp) = &spec.system_prompt {
            cmd.args(["-c", &format!("instructions={:?}", sp)]);
        }
        if let Some(sandbox) = spec.mcp_configs.first() {
            // repurpose first mcp_config field as sandbox mode if set for codex
            cmd.args(["-c", &format!("sandbox_mode={:?}", sandbox)]);
        }
        // Effort maps to reasoning_effort in codex config
        if let Some(effort) = &spec.effort {
            cmd.args(["-c", &format!("reasoning_effort={:?}", effort)]);
        }
        if let Some(mt) = spec.max_turns {
            cmd.args(["-c", &format!("max_turns={}", mt)]);
        }

        cmd.arg(&spec.action_prompt);

        Ok(cmd)
    }

    fn extract_outcome(&self, log: &str, exit_code: i32) -> Outcome {
        extract_text_outcome(log, exit_code)
    }
}
