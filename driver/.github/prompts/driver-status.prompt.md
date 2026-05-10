---
description: Show driver state — recent dispatches, in-flight sessions, last seen timestamps
---

1. Query `state/seen.sqlite` for the 20 most recently dispatched rows:

```python
import sqlite3
conn = sqlite3.connect("state/seen.sqlite")
rows = conn.execute(
    "SELECT task_id, list_id, dispatched_at, session_id, status FROM seen ORDER BY dispatched_at DESC LIMIT 20"
).fetchall()
```

2. Fetch current live status for each session:

```bash
python3 .claude/skills/orchapi-client/client.py list-sessions --status running --limit 20
python3 .claude/skills/orchapi-client/client.py list-sessions --status queued --limit 20
```

3. Print a formatted table: task_id (truncated to 16 chars), dispatched_at (human-readable), session_id (first 8 chars), orchapi status (running / queued / done / cancelled / failed).
