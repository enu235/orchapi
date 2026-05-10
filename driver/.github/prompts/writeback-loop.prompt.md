---
description: Start the writeback worker — subscribes to orchapi SSE and PATCHes Microsoft Graph when sessions complete
---

Run the writeback worker in the foreground:

```bash
python3 .claude/skills/todo-writeback/writeback.py
```

Before starting, verify `state/token_cache.bin` exists. If it is missing, remind the user to run:

```bash
python3 .claude/skills/todo-poll/poll.py --login
```

and abort. The token cache requires `Tasks.ReadWrite` + `Group.ReadWrite.All` scopes.

Report any startup errors. The worker subscribes to the orchapi SSE stream at `GET /writeback/stream` and PATCHes Microsoft To-Do (and Planner, if linked) when sessions reach a terminal state. It runs until interrupted (Ctrl-C).
