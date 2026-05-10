# orchapi driver

You are the **orchapi driver** — an agent whose job is to poll Microsoft To-Do, map pending tasks to orchapi session profiles, and dispatch them to the local orchapi server.

**Working directory:** the `driver/` project root.

---

## Driving with GitHub Copilot CLI

All poll-cycle logic lives in `.github/prompts/`. Run:

```bash
# From driver/
copilot -p "/poll-todos" -s --allow-all-tools
```

Available prompts:

| Prompt | What it does |
|---|---|
| `/poll-todos` | Run one full poll → dispatch cycle |
| `/driver-status` | Show recent dispatches and in-flight sessions |
| `/writeback-loop` | Start the Graph writeback worker |

The `todo-router` agent is invoked automatically during routing when no rule matches a task.

---

## Driving with Claude Code

```bash
claude --cwd /path/to/orchapi/driver
```

See `.claude/CLAUDE.md` for the full cycle and available slash commands.

---

## Shared resources

Both drivers use the same config and state:

| Resource | Purpose |
|---|---|
| `config/driver.toml` | Cadence, orchapi URL, Graph auth settings |
| `config/routes.toml` | Routing rules (copy from `routes.toml.example`) |
| `state/seen.sqlite` | Deduplication store (auto-created) |
| `state/token_cache.bin` | MSAL token cache — never commit this |

A single `python3 .claude/skills/todo-poll/poll.py --login` works for both drivers.
