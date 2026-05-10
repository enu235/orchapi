use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct ServerConfig {
    pub bind: String,
    pub data_dir: PathBuf,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind: "127.0.0.1:7878".into(),
            data_dir: PathBuf::from("./.orchapi"),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct ConcurrencyConfig {
    pub global: usize,
    pub claude: usize,
    pub copilot: usize,
    pub codex: usize,
}

impl ConcurrencyConfig {
    pub fn normalized(&self) -> Self {
        let global = if self.global == 0 { 4 } else { self.global };
        Self {
            global,
            claude: if self.claude == 0 { 2 } else { self.claude },
            copilot: if self.copilot == 0 { 2 } else { self.copilot },
            codex: if self.codex == 0 { 2 } else { self.codex },
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct ClaudeDefaults {
    pub model: Option<String>,
    pub permission_mode: Option<String>,
    pub allowed_tools: Vec<String>,
    pub disallowed_tools: Vec<String>,
    pub max_budget_usd: Option<f64>,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct CopilotDefaults {
    pub model: Option<String>,
    pub allow_all_tools: bool,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct CodexDefaults {
    pub model: Option<String>,
    pub sandbox: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct DefaultsConfig {
    pub cwd: Option<String>,
    pub env: HashMap<String, String>,
    pub cancel_grace_seconds: Option<u64>,
    pub claude: ClaudeDefaults,
    pub copilot: CopilotDefaults,
    pub codex: CodexDefaults,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub concurrency: ConcurrencyConfig,
    pub defaults: DefaultsConfig,
}

impl AppConfig {
    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading config file: {}", path.display()))?;
        let cfg: AppConfig = toml::from_str(&text)
            .with_context(|| format!("parsing config file: {}", path.display()))?;
        Ok(cfg)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProfileFile {
    pub agent: Option<String>,
    pub system_prompt: Option<String>,
    pub overrides: Option<ProfileOverrides>,
}

impl Default for ProfileFile {
    fn default() -> Self {
        Self {
            agent: None,
            system_prompt: None,
            overrides: None,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Profile {
    pub name: String,
    pub agent: Option<String>,
    pub system_prompt: Option<String>,
    pub overrides: Option<ProfileOverrides>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct ProfileOverrides {
    pub model: Option<String>,
    pub cwd: Option<String>,
    pub env: HashMap<String, String>,
    pub allowed_tools: Vec<String>,
    pub disallowed_tools: Vec<String>,
    pub max_turns: Option<u32>,
    pub permission_mode: Option<String>,
    pub mcp_configs: Vec<String>,
    pub plugin_dirs: Vec<String>,
    pub effort: Option<String>,
    pub max_budget_usd: Option<f64>,
}

#[derive(Debug, Clone)]
pub struct ProfileStore {
    pub profiles: HashMap<String, Profile>,
}

impl ProfileStore {
    pub fn load(dir: &Path) -> Result<Self> {
        let mut profiles = HashMap::new();
        if !dir.exists() {
            return Ok(Self { profiles });
        }
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("toml") {
                continue;
            }
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_string();
            let text = std::fs::read_to_string(&path)
                .with_context(|| format!("reading profile: {}", path.display()))?;
            let pf: ProfileFile = toml::from_str(&text)
                .with_context(|| format!("parsing profile: {}", path.display()))?;
            let profile = Profile {
                name: name.clone(),
                agent: pf.agent,
                system_prompt: pf.system_prompt,
                overrides: pf.overrides,
            };
            profiles.insert(name, profile);
        }
        Ok(Self { profiles })
    }

    pub fn get(&self, name: &str) -> Option<&Profile> {
        self.profiles.get(name)
    }

    pub fn list(&self) -> Vec<&Profile> {
        let mut v: Vec<&Profile> = self.profiles.values().collect();
        v.sort_by(|a, b| a.name.cmp(&b.name));
        v
    }
}
