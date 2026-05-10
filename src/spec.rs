use crate::config::{AppConfig, Profile};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct TodoRef {
    pub list_id: String,
    pub task_id: String,
    pub etag: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct PlannerRef {
    pub task_id: String,
    pub etag: String,
    pub plan_id: String,
    pub bucket_id: String,
    pub details_etag: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct ExternalTaskRef {
    pub source: String,
    pub todo: Option<TodoRef>,
    pub planner: Option<PlannerRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AgentKind {
    Claude,
    Copilot,
    Codex,
}

impl std::fmt::Display for AgentKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Claude => write!(f, "claude"),
            Self::Copilot => write!(f, "copilot"),
            Self::Codex => write!(f, "codex"),
        }
    }
}

impl std::str::FromStr for AgentKind {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "claude" => Ok(Self::Claude),
            "copilot" => Ok(Self::Copilot),
            "codex" => Ok(Self::Codex),
            _ => Err(anyhow::anyhow!("unknown agent kind: {s}")),
        }
    }
}

/// Fully resolved session specification, snapshotted at session creation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSpec {
    pub agent: AgentKind,
    pub model: Option<String>,
    pub system_prompt: Option<String>,
    pub action_prompt: String,
    pub cwd: String,
    pub env: HashMap<String, String>,
    pub allowed_tools: Vec<String>,
    pub disallowed_tools: Vec<String>,
    pub permission_mode: Option<String>,
    pub mcp_configs: Vec<String>,
    pub plugin_dirs: Vec<String>,
    pub max_turns: Option<u32>,
    pub max_budget_usd: Option<f64>,
    pub effort: Option<String>,
    pub agent_name: Option<String>,
    pub cancel_grace_seconds: u64,
    /// vars used for template interpolation ({{key}})
    pub vars: HashMap<String, String>,
    #[serde(default)]
    pub external_task: Option<ExternalTaskRef>,
}

/// Partial override from the API request body
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct SessionSpecPartial {
    pub model: Option<String>,
    pub system_prompt: Option<String>,
    pub action_prompt: Option<String>,
    pub cwd: Option<String>,
    pub env: HashMap<String, String>,
    pub allowed_tools: Vec<String>,
    pub disallowed_tools: Vec<String>,
    pub permission_mode: Option<String>,
    pub mcp_configs: Vec<String>,
    pub plugin_dirs: Vec<String>,
    pub max_turns: Option<u32>,
    pub max_budget_usd: Option<f64>,
    pub effort: Option<String>,
    pub agent_name: Option<String>,
    pub cancel_grace_seconds: Option<u64>,
    pub vars: HashMap<String, String>,
    pub parent_session: Option<String>,
    pub tags: Vec<String>,
    #[serde(default)]
    pub external_task: Option<ExternalTaskRef>,
}

/// Build a fully resolved SessionSpec by merging defaults → profile → overrides.
pub fn resolve_spec(
    agent: AgentKind,
    profile: Option<&Profile>,
    overrides: &SessionSpecPartial,
    config: &AppConfig,
) -> anyhow::Result<SessionSpec> {
    // Collect vars first so we can interpolate everything else
    let mut vars = HashMap::new();
    if let Some(p) = profile {
        if let Some(po) = &p.overrides {
            for (k, v) in &po.env {
                vars.insert(k.clone(), v.clone());
            }
        }
    }
    vars.extend(overrides.vars.clone());

    let interpolate = |s: &str| -> String {
        let mut out = s.to_string();
        for (k, v) in &vars {
            out = out.replace(&format!("{{{{{k}}}}}"), v);
        }
        out
    };

    // cwd: defaults → profile → override
    let cwd = overrides
        .cwd
        .as_deref()
        .or_else(|| {
            profile.and_then(|p| p.overrides.as_ref()?.cwd.as_deref())
        })
        .or_else(|| config.defaults.cwd.as_deref())
        .unwrap_or("/tmp")
        .to_string();
    let cwd = interpolate(&cwd);

    // system_prompt: profile wins if no override
    let system_prompt = overrides
        .system_prompt
        .clone()
        .or_else(|| profile.and_then(|p| p.system_prompt.clone()));

    // action_prompt is required in overrides
    let action_prompt = overrides
        .action_prompt
        .clone()
        .ok_or_else(|| anyhow::anyhow!("action_prompt is required"))?;

    // env: defaults < profile < override (merge, not replace)
    let mut env = config.defaults.env.clone();
    if let Some(p) = profile {
        if let Some(po) = &p.overrides {
            env.extend(po.env.clone());
        }
    }
    env.extend(overrides.env.clone());

    // agent-specific defaults
    let (default_model, default_permission_mode, default_allowed, default_effort, default_budget) =
        match &agent {
            AgentKind::Claude => (
                config.defaults.claude.model.clone(),
                config.defaults.claude.permission_mode.clone(),
                config.defaults.claude.allowed_tools.clone(),
                config.defaults.claude.effort.clone(),
                config.defaults.claude.max_budget_usd,
            ),
            AgentKind::Copilot => (
                config.defaults.copilot.model.clone(),
                None,
                vec![],
                config.defaults.copilot.effort.clone(),
                None,
            ),
            AgentKind::Codex => (
                config.defaults.codex.model.clone(),
                None,
                vec![],
                None,
                None,
            ),
        };

    let model = overrides
        .model
        .clone()
        .or_else(|| profile.and_then(|p| p.overrides.as_ref()?.model.clone()))
        .or(default_model);

    let permission_mode = overrides
        .permission_mode
        .clone()
        .or_else(|| profile.and_then(|p| p.overrides.as_ref()?.permission_mode.clone()))
        .or(default_permission_mode);

    let allowed_tools = if !overrides.allowed_tools.is_empty() {
        overrides.allowed_tools.clone()
    } else if let Some(p) = profile {
        if let Some(po) = &p.overrides {
            if !po.allowed_tools.is_empty() {
                po.allowed_tools.clone()
            } else {
                default_allowed
            }
        } else {
            default_allowed
        }
    } else {
        default_allowed
    };

    let disallowed_tools = if !overrides.disallowed_tools.is_empty() {
        overrides.disallowed_tools.clone()
    } else if let Some(p) = profile {
        p.overrides
            .as_ref()
            .map(|po| po.disallowed_tools.clone())
            .unwrap_or_default()
    } else {
        config.defaults.claude.disallowed_tools.clone()
    };

    let max_turns = overrides
        .max_turns
        .or_else(|| profile.and_then(|p| p.overrides.as_ref()?.max_turns));

    let max_budget_usd = overrides
        .max_budget_usd
        .or_else(|| profile.and_then(|p| p.overrides.as_ref()?.max_budget_usd))
        .or(default_budget);

    let effort = overrides
        .effort
        .clone()
        .or_else(|| profile.and_then(|p| p.overrides.as_ref()?.effort.clone()))
        .or(default_effort);

    let mcp_configs: Vec<String> = if !overrides.mcp_configs.is_empty() {
        overrides.mcp_configs.clone()
    } else if let Some(p) = profile {
        p.overrides
            .as_ref()
            .map(|po| po.mcp_configs.clone())
            .unwrap_or_default()
    } else {
        vec![]
    };

    let plugin_dirs: Vec<String> = if !overrides.plugin_dirs.is_empty() {
        overrides.plugin_dirs.clone()
    } else if let Some(p) = profile {
        p.overrides
            .as_ref()
            .map(|po| po.plugin_dirs.clone())
            .unwrap_or_default()
    } else {
        vec![]
    };

    let cancel_grace_seconds = overrides
        .cancel_grace_seconds
        .or(config.defaults.cancel_grace_seconds)
        .unwrap_or(10);

    Ok(SessionSpec {
        agent,
        model,
        system_prompt,
        action_prompt,
        cwd,
        env,
        allowed_tools,
        disallowed_tools,
        permission_mode,
        mcp_configs,
        plugin_dirs,
        max_turns,
        max_budget_usd,
        effort,
        agent_name: overrides.agent_name.clone(),
        cancel_grace_seconds,
        vars,
        external_task: overrides.external_task.clone(),
    })
}
