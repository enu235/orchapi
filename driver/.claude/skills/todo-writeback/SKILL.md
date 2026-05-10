---
name: todo-writeback
description: Long-running worker that subscribes to the orchapi SSE writeback stream and PATCHes Microsoft Graph (To-Do + Planner) when sessions reach a terminal state.
---

# todo-writeback

Subscribes to `GET /writeback/stream` on the local orchapi server and processes
each completed session that carries an `external_task` reference. For every
session it claims the writeback, gathers the session record + events, then
writes a summary back to Microsoft To-Do (and the linked Planner task, if any)
via Graph PATCH. Falls back to polling `/sessions?writeback_status=pending` on
a configurable interval in case SSE drops.

## Usage

```bash
python3 .claude/skills/todo-writeback/writeback.py
```

Runs in the foreground. Logs status to stderr, summaries to stdout. Ctrl-C
to stop.

## Requirements

- `state/token_cache.bin` populated with `Tasks.ReadWrite` and
  `Group.ReadWrite.All` scopes. If you upgraded from the older `Tasks.Read`
  cache, run `python3 .claude/skills/todo-poll/poll.py --login` once to
  re-consent, then start this worker.
- orchapi reachable at `[orchapi].base_url`.
- `[writeback]` section present in `config/driver.toml`.
