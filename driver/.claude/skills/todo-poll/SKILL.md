# Todo Poll Skill

Polls Microsoft To-Do via MS Graph and returns a JSON array of all pending (non-completed) tasks across all lists.

## Usage

```bash
python3 .claude/skills/todo-poll/poll.py           # fetch and print JSON
python3 .claude/skills/todo-poll/poll.py --login   # force device-code re-auth
```

## Output schema (each item)

```json
{
  "id": "AAMkAGE1...",
  "listId": "AAMkAGE1...",
  "listName": "Coding",
  "title": "Fix the login bug",
  "body": "See ticket #123",
  "due": "2026-05-15T00:00:00.0000000",
  "importance": "normal",
  "status": "notStarted",
  "etag": "W/\"...\"",
  "lastModified": "2026-05-09T14:00:00Z"
}
```

## Config (`config/driver.toml`)

```toml
[graph]
mode = "msal"              # "msal" (default) or "powershell"
client_id = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
tenant = "common"
scopes = ["Tasks.Read"]
token_cache_path = "./state/token_cache.bin"
pwsh_script = "../Get-PendingTodos.ps1"  # powershell mode only
```
