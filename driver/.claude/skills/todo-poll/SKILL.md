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
  "lastModified": "2026-05-09T14:00:00Z",
  "source": "todo",
  "planner": null
}
```

When a task is linked to Microsoft Planner, `source` is `"planner"` and `planner` contains enrichment data:

```json
{
  "source": "planner",
  "planner": {
    "task_id": "abc123",
    "etag": "W/\"...\"",
    "plan_id": "plan456",
    "bucket_id": "bucket789",
    "percent_complete": 25,
    "priority": 5,
    "details_etag": "W/\"...\"",
    "description": "Implementation notes",
    "checklist": [
      { "id": "item1", "title": "Write tests", "isChecked": false },
      { "id": "item2", "title": "Review PR", "isChecked": true }
    ],
    "web_url": "https://tasks.office.com/..."
  }
}
```

## Config (`config/driver.toml`)

```toml
[graph]
mode = "msal"              # "msal" (default) or "powershell"
client_id = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
tenant = "common"
scopes = ["Tasks.ReadWrite", "Group.ReadWrite.All"]
token_cache_path = "./state/token_cache.bin"
pwsh_script = "../Get-PendingTodos.ps1"  # powershell mode only
```
