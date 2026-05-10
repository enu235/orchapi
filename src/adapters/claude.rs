use crate::adapters::AgentAdapter;
use crate::outcome::{extract_claude_outcome, Outcome};
use crate::spec::{AgentKind, SessionSpec};
use anyhow::Result;
use tokio::process::Command;

pub struct ClaudeAdapter;

impl AgentAdapter for ClaudeAdapter {
    fn kind(&self) -> AgentKind {
        AgentKind::Claude
    }

    fn build_command(&self, spec: &SessionSpec) -> Result<Command> {
        let mut cmd = Command::new("claude");
        cmd.current_dir(&spec.cwd);
        cmd.envs(&spec.env);

        cmd.arg("--print");
        cmd.arg("--verbose");
        cmd.args(["--output-format", "stream-json"]);
        cmd.arg("--include-partial-messages");

        if let Some(model) = &spec.model {
            cmd.args(["--model", model]);
        }
        if let Some(sp) = &spec.system_prompt {
            cmd.args(["--append-system-prompt", sp]);
        }
        if let Some(pm) = &spec.permission_mode {
            cmd.args(["--permission-mode", pm]);
        }
        if !spec.allowed_tools.is_empty() {
            cmd.arg("--allowed-tools");
            cmd.args(&spec.allowed_tools);
        }
        if !spec.disallowed_tools.is_empty() {
            cmd.arg("--disallowed-tools");
            cmd.args(&spec.disallowed_tools);
        }
        for dir in &spec.plugin_dirs {
            cmd.args(["--plugin-dir", dir]);
        }
        for mc in &spec.mcp_configs {
            cmd.args(["--mcp-config", mc]);
        }
        if let Some(budget) = spec.max_budget_usd {
            cmd.args(["--max-budget-usd", &budget.to_string()]);
        }
        if let Some(effort) = &spec.effort {
            cmd.args(["--effort", effort]);
        }
        if let Some(mt) = spec.max_turns {
            // Claude Code doesn't have --max-turns yet; inject via system prompt note
            cmd.args([
                "--append-system-prompt",
                &format!("(Stop after at most {mt} turns of tool use.)"),
            ]);
        }

        cmd.arg("--");
        cmd.arg(&spec.action_prompt);

        Ok(cmd)
    }

    fn extract_outcome(&self, log: &str, exit_code: i32) -> Outcome {
        extract_claude_outcome(log, exit_code)
    }
}
