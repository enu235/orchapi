# Todo Writeback Skill

Long-running worker that subscribes to the orchapi SSE writeback stream and PATCHes Microsoft Graph (To-Do + Planner) when sessions reach a terminal state.

**Script:** `.claude/skills/todo-writeback/writeback.py` (shared with the Claude Code driver)

## Usage

```bash
python3 .claude/skills/todo-writeback/writeback.py
```

Runs in the foreground. Requires `state/token_cache.bin` with `Tasks.ReadWrite` and `Group.ReadWrite.All` scopes.

For full requirements and config reference, see `.claude/skills/todo-writeback/SKILL.md`.
