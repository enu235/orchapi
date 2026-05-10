# Todo Router Skill

Maps a To-Do task to an orchapi session configuration using rules in `config/routes.toml`. Returns immediately without invoking an LLM.

## Usage

```bash
echo '<task-json>' | python3 .claude/skills/todo-router/router.py
python3 .claude/skills/todo-router/router.py /path/to/task.json
```

## Output (one JSON line)

| Result | Meaning |
|--------|---------|
| `{"profile": "...", "cwd": "...", "overrides": {}}` | Matched a rule — proceed to dispatch |
| `{"action": "skip"}` | Explicitly skipped by rule or default |
| `{"action": "llm_fallback"}` | No rule matched — let the `todo-router` agent decide |

## Config (`config/routes.toml`)

Rules are checked top-to-bottom; first match wins. Both `list` and `title_match` are optional — omit either to match all values.

```toml
[[routes]]
list = "Coding"
profile = "example"
cwd = "/path/to/your/dev/dir"

[[routes]]
title_match = "(?i)\\bPR\\b"
profile = "pr-reviewer"
cwd = "/path/to/your/dev/dir"

[default]
unmatched_action = "llm_fallback"  # "llm_fallback" | "skip" | "default_profile"
fallback_profile = "example"
fallback_cwd = "/tmp"
```
