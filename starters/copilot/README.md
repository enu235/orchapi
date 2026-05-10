# Copilot CLI starter environment

This directory is a minimal GitHub Copilot CLI workspace for orchapi child sessions. Copy it into your project and point a route at it.

## Prerequisites

```bash
# Install GitHub Copilot CLI
npm install -g @github/copilot-cli          # or the current package name — see INSTALL.md

# Authenticate
gh auth login
gh extension install github/gh-copilot
copilot --version                           # verify
```

## Setup

```bash
# 1. Copy the starter into your project
cp -r /path/to/orchapi/starters/copilot ~/dev/my-project-copilot

# 2. Add a profile with agent = "copilot" in orchapi profiles/
```

```toml
# profiles/copilot-default.toml
agent         = "copilot"
system_prompt = "You are a software engineering agent completing To-Do tasks."

[overrides]
allowed_tools = ["read_file", "write_file", "run_terminal_cmd", "search_files"]
```

```bash
# 3. Add a route in driver/config/routes.toml pointing at this cwd
```

```toml
[[routes]]
list    = "Coding"
profile = "copilot-default"
cwd     = "/Users/you/dev/my-project-copilot"
```

## Customising

- **`AGENTS.md`** — project-level instructions Copilot reads automatically. Add tech stack, conventions, file layout, test commands.
- **`.github/copilot-instructions.md`** — supplemental repo-wide instructions.
- **`.github/agents/`** — place custom `*.agent.md` files here to define task-specific sub-agents.
- **`.github/skills/`** — place `<name>/SKILL.md` skill definitions here. Copilot CLI discovers them automatically.
- **`.github/prompts/`** — reusable prompt files (`*.prompt.md`) for common task patterns.

## Important: no `--cwd` flag

Copilot CLI has no `--cwd` flag. orchapi sets the working directory by changing the process's cwd to this directory before spawning `copilot`. Paths in your `AGENTS.md` that reference files should be relative to the root of this directory.

If the task needs to reach files in other directories, the agent can use the shell — just be aware that Copilot's `--add-dir` flag can be passed via the profile's `plugin_dirs` field if needed.

## How it works

When orchapi dispatches a session to this `cwd`, Copilot CLI is invoked with the task's `action_prompt`. Copilot reads `AGENTS.md` and `.github/copilot-instructions.md`, does the work, and exits. The orchapi writeback worker PATCHes Microsoft To-Do with the outcome.

## See also

- [orchapi executor docs](../../docs/executors/copilot.md)
- [Routing rules](../../docs/driver-router.md)
- [Profiles reference](../../docs/profiles.md)
