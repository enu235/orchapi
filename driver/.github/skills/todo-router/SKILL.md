# Todo Router Skill

Maps a To-Do task to an orchapi session configuration using rules in `config/routes.toml`.

**Script:** `.claude/skills/todo-router/router.py` (shared with the Claude Code driver)

## Usage

```bash
echo '<task-json>' | python3 .claude/skills/todo-router/router.py
python3 .claude/skills/todo-router/router.py /path/to/task.json
```

For full output schema and config reference, see `.claude/skills/todo-router/SKILL.md`.
