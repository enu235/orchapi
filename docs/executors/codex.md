# OpenAI Codex CLI executor

Codex CLI is supported as an **executor** only — it spawns child sessions that work on individual tasks. It does not serve as a driver because its CLI lacks native custom-agents and skills support (everything must be inlined into `AGENTS.md`).

---

## Install

```bash
# Requires Node.js 18+
npm install -g @openai/codex

# Or via pip
pip install openai-codex

# Verify
codex --version
```

---

## Authenticate

```bash
# Set your OpenAI API key
export OPENAI_API_KEY=sk-...

# Persist it (add to ~/.zshrc or ~/.bashrc)
echo 'export OPENAI_API_KEY=sk-...' >> ~/.zshrc
```

Alternatively, place the key in `~/.codex/auth.json`:

```json
{
  "OPENAI_API_KEY": "sk-..."
}
```

---

## Using as an executor (child sessions)

### Set up the starter environment

```bash
cp -r /path/to/orchapi/starters/codex ~/dev/my-project-codex
```

Then create a profile and route:

```toml
# profiles/codex-default.toml
agent         = "codex"
model         = "codex-mini-latest"
system_prompt = "You are a software engineering agent completing To-Do tasks."
```

```toml
# driver/config/routes.toml
[[routes]]
list    = "Coding"
profile = "codex-default"
cwd     = "/Users/you/dev/my-project-codex"
```

### Customising the starter

**`AGENTS.md`** is the primary instruction file. Codex walks from the Git root down to the working directory and loads every `AGENTS.md` it finds (later files take precedence). Add:

- Tech stack and language version
- How to run tests
- Coding conventions and file layout
- Any constraints the agent should respect

**`.codex/config.toml`** sets local config that overrides `~/.codex/config.toml`:

```toml
model        = "codex-mini-latest"
sandbox_mode = "workspace-write"   # read-only | workspace-write | danger-full-access
auto_approve = true                # required for non-interactive orchapi sessions
```

---

## How orchapi invokes Codex CLI

```
codex exec [-m <model>] [-c instructions=<system_prompt>] \
           [-c sandbox_mode=<mode>] [-c reasoning_effort=<effort>] \
           [-c max_turns=<n>] \
           <action_prompt>
```

The process is launched with its working directory set to the route's `cwd` (via the OS-level cwd, equivalent to `codex exec -C <cwd>`). Codex reads `AGENTS.md` from each ancestor directory automatically.

---

## Sandbox mode

Codex isolates the agent's file access via the `sandbox_mode` setting. The starter defaults to `workspace-write`:

| Mode | Reads | Writes |
|---|---|---|
| `read-only` | Anywhere | Nowhere |
| `workspace-write` | Anywhere | Within working directory only |
| `danger-full-access` | Anywhere | Anywhere |

The mode is passed to Codex via `mcp_configs[0]` in the orchapi adapter (see `src/adapters/codex.rs`). To override it per-task, set `mcp_configs` in the session spec or profile.

---

## Profile fields supported by Codex

| Field | Support |
|---|---|
| `model` | Yes (`-m`) |
| `system_prompt` | Yes (`-c instructions=...`) |
| `effort` | Yes (`-c reasoning_effort=...`) |
| `max_turns` | Yes (`-c max_turns=...`) |
| `mcp_configs[0]` | Repurposed as `sandbox_mode` (current adapter limitation) |
| `plugin_dirs` | Not supported |
| `permission_mode` | Not supported |
| `disallowed_tools` | Not supported |
| `max_budget_usd` | Not supported |

See [docs/adapters.md](../adapters.md) for the full parity table.

---

## Codex profiles (native)

Codex CLI has its own profile system (`~/.codex/config.toml`, `[profile.<name>]` sections) separate from orchapi profiles. You can use them alongside orchapi profiles if needed, but they are not required.

---

## Gotchas

- **`auto_approve = true` is required.** Codex prompts for approval before each action in interactive mode. Set `auto_approve = true` in `.codex/config.toml` or the session will hang waiting for input.
- **`AGENTS.md` only.** Codex does not support custom agents, skills, or prompt files. All task framing must go in `AGENTS.md`.
- **sandbox_mode via mcp_configs.** The current orchapi adapter maps `mcp_configs[0]` to `sandbox_mode`. This is a known limitation tracked in [docs/adapters.md](../adapters.md). Set the mode in `.codex/config.toml` as the preferred alternative.
- **Cost model.** Codex charges per token against your OpenAI account. Set spending limits in your OpenAI dashboard if you're concerned about runaway costs.
