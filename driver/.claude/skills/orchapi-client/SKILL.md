# Orchapi Client Skill

Thin wrapper around the orchapi REST API (`http://127.0.0.1:7878` by default).

## Usage

```bash
# List available profiles
python3 .claude/skills/orchapi-client/client.py list-profiles

# Dispatch a session
python3 .claude/skills/orchapi-client/client.py create-session --spec '{
  "agent": "claude",
  "profile": "example",
  "overrides": {
    "action_prompt": "Fix the login bug\n---\nSource: Microsoft To-Do | Task ID: AAMkAGE1...",
    "cwd": "/Users/allan/dev/myapp"
  }
}'

# Inspect a session
python3 .claude/skills/orchapi-client/client.py get-session <session-id>

# List sessions (filterable)
python3 .claude/skills/orchapi-client/client.py list-sessions --status running --limit 20

# Count running + queued sessions (for in-flight cap check)
python3 .claude/skills/orchapi-client/client.py count-running
```

## Config (`config/driver.toml`)

```toml
[orchapi]
base_url = "http://127.0.0.1:7878"
max_in_flight = 4
```
