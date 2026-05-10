# orchapi driver

The driver is a Claude Code workspace that polls Microsoft To-Do and Planner, routes tasks to orchapi session profiles, and dispatches them automatically.

**Full documentation:** [`/docs/driver.md`](../docs/driver.md)

---

## Quick start

```bash
# 1. Install dependencies (creates driver/.venv automatically via the installer)
pip install -r requirements.txt          # or: source .venv/bin/activate

# 2. Authenticate with Microsoft Graph (first time only)
python3 .claude/skills/todo-poll/poll.py --login

# 3. Configure your routing rules
cp config/routes.toml.example config/routes.toml
# Edit routes.toml — map your To-Do list names to orchapi profiles

# 4. Open the driver in Claude Code
claude --cwd /path/to/orchapi/driver
```

Inside Claude Code:

| Command | What it does |
|---|---|
| `/poll-todos` | Run one poll → dispatch cycle |
| `/loop 5m /poll-todos` | Start the recurring loop (every 5 min) |
| `/writeback-loop` | Start the Graph writeback worker |
| `/driver-status` | Show recent dispatches and live sessions |

---

## Configuration

| File | Purpose |
|---|---|
| `config/driver.toml` | Cadence, orchapi URL, Graph auth settings |
| `config/routes.toml` | Routing rules (copy from `routes.toml.example`) |
| `state/seen.sqlite` | Deduplication store (auto-created) |
| `state/token_cache.bin` | MSAL token cache — never commit this |

See [`/docs/microsoft-graph.md`](../docs/microsoft-graph.md) for auth setup and scope requirements.

---

## Further reading

- [Driver overview](../docs/driver.md)
- [Poll cycle](../docs/driver-poll.md)
- [Routing rules](../docs/driver-router.md)
- [Writeback](../docs/driver-writeback.md)
- [Troubleshooting](../docs/troubleshooting.md)
