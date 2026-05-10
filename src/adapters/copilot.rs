use crate::adapters::AgentAdapter;
use crate::outcome::{extract_text_outcome, Outcome};
use crate::spec::{AgentKind, SessionSpec};
use anyhow::Result;
use std::io::Write;
use tempfile::NamedTempFile;
use tokio::process::Command;

pub struct CopilotAdapter;

impl AgentAdapter for CopilotAdapter {
    fn kind(&self) -> AgentKind {
        AgentKind::Copilot
    }

    fn build_command(&self, spec: &SessionSpec) -> Result<Command> {
        let mut cmd = Command::new("copilot");
        cmd.current_dir(&spec.cwd);
        cmd.envs(&spec.env);

        // Build the prompt: prepend system prompt inline if no --agent flag
        let (prompt, agent_file) = if let Some(sp) = &spec.system_prompt {
            if let Some(name) = &spec.agent_name {
                // Write a temporary agent definition file
                let agent_def = serde_json::json!({
                    "name": name,
                    "description": "orchapi managed agent",
                    "instructions": sp
                });
                let mut tmp = NamedTempFile::new()?;
                write!(tmp, "{}", agent_def)?;
                // Keep the temp file alive by leaking — the process will outlive this scope.
                // We persist the path and the OS cleans up on exit.
                let path = tmp.path().to_string_lossy().into_owned();
                tmp.keep().ok();
                (spec.action_prompt.clone(), Some(path))
            } else {
                // No agent name: prepend system prompt to action prompt
                (format!("{sp}\n\n{}", spec.action_prompt), None)
            }
        } else {
            (spec.action_prompt.clone(), None)
        };

        cmd.args(["--prompt", &prompt]);

        if let Some(model) = &spec.model {
            if model != "default" {
                cmd.args(["--model", model]);
            }
        }
        cmd.arg("--allow-all-tools");

        if let Some(ref af) = agent_file {
            cmd.args(["--agent", af]);
        } else if let Some(name) = &spec.agent_name {
            cmd.args(["--agent", name]);
        }

        for dir in &spec.plugin_dirs {
            cmd.args(["--add-dir", dir]);
        }
        for mc in &spec.mcp_configs {
            cmd.args(["--additional-mcp-config", mc]);
        }
        if let Some(effort) = &spec.effort {
            cmd.args(["--effort", effort]);
        }

        Ok(cmd)
    }

    fn extract_outcome(&self, log: &str, exit_code: i32) -> Outcome {
        extract_text_outcome(log, exit_code)
    }
}
