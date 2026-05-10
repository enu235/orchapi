# Codex CLI starter environment

This directory is a minimal OpenAI Codex CLI workspace for orchapi child sessions. Copy it into your project and point a route at it.

## Prerequisites

```bash
# Install Codex CLI
npm install -g @openai/codex             # or: pip install openai-codex

# Authenticate (API key)
export OPENAI_API_KEY=sk-...            # add to ~/.zshrc or ~/.bashrc

# Verify
codex --version
```

## Setup

```bash
# 1. Copy the starter into your project
cp -r /path/to/orchapi/starters/codex ~/dev/my-project-codex

# 2. Add a profile with agent = "codex" in orchapi profiles/
```

```toml
# profiles/codex-default.toml
agent         = "codex"
system_prompt = "You are a software engineering agent completing To-Do tasks."
model         = "codex-mini-latest"

[overrides]
# sandbox_mode is passed via mcp_configs[0] in the Codex adapter.
# Leave it unset here to use .codex/config.toml's default.
```

```bash
# 3. Add a route in driver/config/routes.toml pointing at this cwd
```

```toml
[[routes]]
list    = "Coding"
profile = "codex-default"
cwd     = "/Users/you/dev/my-project-codex"
```

## Customising

- **`AGENTS.md`** — project-level instructions Codex reads automatically (walks from Git root to cwd, loading each `AGENTS.md`). Add tech stack, conventions, file layout, test commands.
- **`.codex/config.toml`** — local config overrides (`model`, `sandbox_mode`, `auto_approve`). Codex merges this with `~/.codex/config.toml` (local wins).
- **Profiles** — Codex CLI profiles (`--profile ci`) live in `~/.codex/config.toml` under `[profile.ci]`. orchapi profile fields (`model`, `system_prompt`) map to the `codex exec -m` and `-c instructions=...` flags.

## Sandbox note

Codex runs in `workspace-write` mode by default (reads anywhere, writes within the working directory). For tasks that need broader write access, change `sandbox_mode` in `.codex/config.toml` or set it in the profile's `mcp_configs[0]` field (see `src/adapters/codex.rs` for the current mapping).

## How it works

When orchapi dispatches a session to this `cwd`, Codex CLI is invoked with the task's `action_prompt`. Codex reads `AGENTS.md` for context, does the work, and exits. The orchapi writeback worker PATCHes Microsoft To-Do with the outcome.

## See also

- [orchapi executor docs](../../docs/executors/codex.md)
- [Routing rules](../../docs/driver-router.md)
- [Profiles reference](../../docs/profiles.md)
