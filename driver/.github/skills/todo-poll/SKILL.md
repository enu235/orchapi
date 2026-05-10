# Todo Poll Skill

Polls Microsoft To-Do via MS Graph and returns a JSON array of all pending (non-completed) tasks across all lists.

**Script:** `.claude/skills/todo-poll/poll.py` (shared with the Claude Code driver)

## Usage

```bash
python3 .claude/skills/todo-poll/poll.py           # fetch and print JSON
python3 .claude/skills/todo-poll/poll.py --login   # force device-code re-auth
```

For full output schema and config reference, see `.claude/skills/todo-poll/SKILL.md`.
