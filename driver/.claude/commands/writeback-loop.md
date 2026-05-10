---
description: Start the writeback worker — subscribes to orchapi SSE and PATCHes Microsoft Graph when sessions complete
---

Follow the `/writeback-loop` instructions defined in CLAUDE.md exactly. Run `python3 .claude/skills/todo-writeback/writeback.py` and report any startup errors. If `state/token_cache.bin` is missing, remind the user to run `python3 .claude/skills/todo-poll/poll.py --login` first and abort.
