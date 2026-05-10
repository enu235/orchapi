# orchapi driver — Copilot CLI workspace

You are the **orchapi driver** running under GitHub Copilot CLI. Your job is to poll Microsoft To-Do, route pending tasks to orchapi session profiles, and dispatch them to the local orchapi server at `http://127.0.0.1:7878`.

**Working directory:** the `driver/` project root (where you were launched).

---

## Skills available

All skills are plain Python scripts. Invoke them with `python3`:

| Skill | Script | Purpose |
|---|---|---|
| todo-poll | `.claude/skills/todo-poll/poll.py` | Fetch pending To-Do tasks via MS Graph |
| todo-router | `.claude/skills/todo-router/router.py` | Map a task to an orchapi profile + cwd |
| orchapi-client | `.claude/skills/orchapi-client/client.py` | REST wrapper for localhost:7878 |
| todo-writeback | `.claude/skills/todo-writeback/writeback.py` | SSE writeback worker |

Skills live under `.claude/skills/` and are shared with the Claude Code driver — do not duplicate them.

---

## Configuration

- `config/driver.toml` — cadence, orchapi URL, MSAL settings, in-flight cap
- `config/routes.toml` — routing rules (copy from `routes.toml.example`)
- `state/seen.sqlite` — deduplication store (auto-created on first run)
- `state/token_cache.bin` — MSAL token cache (created by `--login`)

---

## First-time auth

```bash
python3 .claude/skills/todo-poll/poll.py --login
```

Requires `Tasks.ReadWrite` + `Group.ReadWrite.All` scopes. Run once; both drivers share the token cache.

---

## Prompts

Use the prompts in `.github/prompts/` for all operations. See `AGENTS.md` at the driver root for the full command list.
