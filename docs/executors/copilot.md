# GitHub Copilot CLI executor

GitHub Copilot CLI can be used both as the **driver** (the agent that polls Microsoft To-Do and dispatches sessions) and as an **executor** (the child agent that works on individual tasks). It is the only alternative to Claude Code that supports both roles.

---

## Install

```bash
# Requires Node.js 18+ and a GitHub Copilot subscription

# Install the GitHub CLI first (if not already installed)
# macOS
brew install gh
# Windows / Linux: https://cli.github.com

# Install the Copilot CLI extension
gh extension install github/gh-copilot

# Verify
copilot --version
```

> **Note:** The `copilot` command is provided by the `gh-copilot` extension. After installation it is available as both `gh copilot` and the standalone `copilot` alias.

---

## Authenticate

```bash
# Sign in to GitHub (includes Copilot access)
gh auth login

# Verify Copilot access
copilot --version
```

You need an active GitHub Copilot Individual, Business, or Enterprise subscription.

---

## Using as the driver

The Copilot driver workspace lives at `driver/.github/`. It shares all Python skills, config, and state with the Claude driver. See [docs/driver.md](../driver.md#github-copilot-cli) for the full workflow.

Quick start:

```bash
# 1. Authenticate with Microsoft Graph (once — shared with Claude driver)
cd /path/to/orchapi/driver
source .venv/bin/activate
python3 .claude/skills/todo-poll/poll.py --login

# 2. Run a poll cycle
copilot -p "/poll-todos" -s --allow-all-tools

# 3. Recurring loop (every 5 minutes)
while true; do
  copilot -p "/poll-todos" -s --allow-all-tools
  sleep 300
done
```

---

## Using as an executor (child sessions)

### Set up the starter environment

```bash
cp -r /path/to/orchapi/starters/copilot ~/dev/my-project-copilot
```

Then point a route at it:

```toml
# profiles/copilot-default.toml
agent         = "copilot"
system_prompt = "You are a software engineering agent completing To-Do tasks."

[overrides]
allowed_tools = ["read_file", "write_file", "run_terminal_cmd", "search_files"]
```

```toml
# driver/config/routes.toml
[[routes]]
list    = "Coding"
profile = "copilot-default"
cwd     = "/Users/you/dev/my-project-copilot"
```

### Customising the starter

**`AGENTS.md`** (repo root) is the primary instruction file Copilot reads. Add tech stack, conventions, test commands, and file layout context.

**`.github/copilot-instructions.md`** supplements `AGENTS.md` with repo-wide instructions.

**`.github/agents/`** — place `*.agent.md` files for task-specific sub-agents (e.g. a `code-review.agent.md` that focuses on PR comments).

**`.github/skills/`** — place `<name>/SKILL.md` files for reusable capabilities. Copilot discovers them automatically from this directory.

**`.github/prompts/`** — reusable `*.prompt.md` files for common task patterns.

---

## How orchapi invokes Copilot CLI

```
copilot --prompt <action_prompt> --allow-all-tools \
        [--model <model>] \
        [--add-dir <plugin_dir>] \
        [--additional-mcp-config <mcp_config_path>]
```

The process is launched with its working directory set to the route's `cwd`. Copilot reads `AGENTS.md` and `.github/copilot-instructions.md` from that directory automatically.

> **No `--cwd` flag.** Copilot CLI does not have a `--cwd` flag — orchapi sets the working directory at the OS process level instead. Paths in `AGENTS.md` should be relative to the project root.

---

## Profile fields supported by Copilot

| Field | Support |
|---|---|
| `model` | Yes (`--model`) |
| `system_prompt` | Yes (prepended to prompt) |
| `plugin_dirs` | Yes (`--add-dir`, repeatable) |
| `mcp_configs` | Yes (`--additional-mcp-config`) |
| `effort` | Yes |
| `permission_mode` | Not supported (always `--allow-all-tools`) |
| `disallowed_tools` | Not supported |
| `max_budget_usd` | Not supported |
| `max_turns` | Not supported |

See [docs/adapters.md](../adapters.md) for the full parity table.

---

## MCP servers

Copilot CLI reads MCP servers from `~/.copilot/mcp-config.json` (root key `mcpServers`, not `servers`). This is the user-level config; project-level MCP is not yet supported by Copilot CLI.

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["/path/to/server.js"]
    }
  }
}
```

---

## Gotchas

- **No built-in loop command.** Use a shell `while` loop or a system cron job for recurring poll cycles. Claude Code's `/loop` skill is not available in Copilot.
- **Tool allow-list.** Copilot uses a different tool naming scheme from Claude (`read_file` vs `Read`, `run_terminal_cmd` vs `Bash`). Set `allowed_tools` in the profile using Copilot's tool names.
- **`--allow-all-tools`.** Orchapi always passes `--allow-all-tools` when launching Copilot child sessions (`permission_mode` is not mapped). If you need to restrict tool access, use Copilot's `.github/` deny instructions.
