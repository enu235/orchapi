# Executor setup guides

An **executor** is any CLI that orchapi spawns to work on a task. This directory has one guide per supported executor:

- [Claude Code](claude.md) — the default; most feature-complete adapter
- [GitHub Copilot CLI](copilot.md) — also works as the **driver** (see [docs/driver.md](../driver.md))
- [OpenAI Codex CLI](codex.md) — executor-only (no driver support yet)

---

## Capability comparison

| Feature | Claude Code | Copilot CLI | Codex CLI |
|---|---|---|---|
| Use as driver | Yes | Yes | No |
| Use as executor | Yes | Yes | Yes |
| Project instructions file | `.claude/CLAUDE.md` | `AGENTS.md` + `.github/copilot-instructions.md` | `AGENTS.md` |
| Custom agents | `.claude/agents/*.md` | `.github/agents/*.agent.md` | — |
| Custom skills | `.claude/skills/<n>/SKILL.md` | `.github/skills/<n>/SKILL.md` | — |
| Reusable prompts/commands | `.claude/commands/*.md` | `.github/prompts/*.prompt.md` | — |
| Per-project config | `.claude/settings.json` | `.github/`, env vars | `.codex/config.toml` |
| Non-interactive flag | `claude -p "..."` | `copilot -p "..." -s` | `codex exec "..."` |
| Working directory flag | `--cwd <dir>` | _(set by shell cwd)_ | `-C <dir>` |
| Model selection | `--model` | `--model` | `-m` |
| Structured output | `--output-format stream-json` | `--output-format json` | `--json` |

---

## Starter environments

Each executor has a starter directory you can copy into your project as a `cwd` for child sessions:

```
starters/
  claude/    # .claude/CLAUDE.md + settings.json
  copilot/   # AGENTS.md + .github/copilot-instructions.md
  codex/     # AGENTS.md + .codex/config.toml
```

See the `README.md` inside each starter for copy-and-route instructions.

---

## Choosing an executor per task

The executor for each child session is determined by the `agent` field in the session's profile (`profiles/<name>.toml`). To route a task to Copilot CLI, create a profile with `agent = "copilot"` and point a route rule at it:

```toml
# profiles/copilot-default.toml
agent         = "copilot"
system_prompt = "You are a software engineering agent completing To-Do tasks."
```

```toml
# driver/config/routes.toml
[[routes]]
list    = "Coding"
profile = "copilot-default"
cwd     = "/Users/you/dev/my-project-copilot"
```

The driver reads the agent kind from the profile at dispatch time (via `client.py get-profile`). You do not need to specify `agent` in the route rule itself.
