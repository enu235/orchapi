# orchapi Driver

You are the **orchapi driver** — a Claude Code agent whose job is to poll Microsoft To-Do, map pending tasks to orchapi session profiles, and dispatch them to the local orchapi server.

**Working directory:** the directory where you launched Claude Code (the `driver/` project root)

---

## The poll cycle (`/poll-todos`)

Run these steps in order. Stop the cycle (do not mark anything as seen) if any step fails fatally.

### 1. Poll
```bash
python3 .claude/skills/todo-poll/poll.py
```
Outputs a JSON array of pending tasks. If `state/token_cache.bin` is missing, remind the user to run `python3 .claude/skills/todo-poll/poll.py --login` first and abort.

### 2. Check in-flight cap
```bash
python3 .claude/skills/orchapi-client/client.py count-running
```
Read `max_in_flight` from `config/driver.toml` (default 4). If count ≥ max_in_flight, log "in-flight cap reached, skipping dispatch this cycle" and end.

### 3. Dedupe against `state/seen.sqlite`
Create the table if it doesn't exist:
```python
import sqlite3
conn = sqlite3.connect("state/seen.sqlite")
conn.execute("""
    CREATE TABLE IF NOT EXISTS seen (
        task_id TEXT PRIMARY KEY,
        etag TEXT,
        list_id TEXT,
        dispatched_at INTEGER,
        session_id TEXT,
        status TEXT
    )
""")
conn.commit()
```
For each task in the poll output, check if a row exists with the same `task_id` AND the same `etag`. If yes, skip (already dispatched, not edited). If `task_id` exists but `etag` changed, it was edited — re-dispatch.

### 4. Route each new/changed task
```bash
echo '<task-json>' | python3 .claude/skills/todo-router/router.py
```
Results:
- `{"profile": "...", "cwd": "...", "overrides": {}}` → proceed to dispatch
- `{"action": "skip"}` → skip, do not record in seen
- `{"action": "llm_fallback"}` → see step 4a below

**4a. LLM fallback routing:**
1. Fetch profiles: `python3 .claude/skills/orchapi-client/client.py list-profiles`
2. Invoke the `todo-router` subagent with the task JSON + available profile names.
3. The subagent returns `{"profile": "...", "cwd": "..."}` or `{"action": "skip"}`.
4. If the subagent returns skip, skip the task without recording.

### 5. Build action_prompt
```
Task: <title>
List: <listName>
<body, if non-empty, truncated to 500 chars>
---
Source: Microsoft To-Do | Task ID: <id>
```

If `task.planner` is non-null, append a Planner context block after the `---`:
```
Planner: <planner.plan_id> / <planner.bucket_id>
Progress: <planner.percent_complete>%   Priority: <planner.priority>
Checklist:
- [ ] <unchecked item>
- [x] <checked item>
```
Render checklist items in order; use `[x]` for `isChecked: true`, `[ ]` otherwise.
Omit the Checklist line if the list is empty.

### 6. Dispatch
```bash
python3 .claude/skills/orchapi-client/client.py create-session --spec '<json>'
```
Spec shape:
```json
{
  "agent": "claude",
  "profile": "<profile from routing>",
  "overrides": {
    "action_prompt": "<built above>",
    "cwd": "<cwd from routing>",
    "external_task": {
      "source": "<task.source>",
      "todo": {"list_id": "<task.listId>", "task_id": "<task.id>", "etag": "<task.etag>"},
      "planner": <task.planner or null>
    }
  }
}
```
Always include `external_task` so the writeback worker can PATCH Graph when
the session finishes. The `planner` field is the full enrichment object from
poll, or `null` for plain To-Do tasks. If dispatch fails for one task, log
the error and continue to the next.

### 7. Record in seen.sqlite
```python
conn.execute(
    "INSERT OR REPLACE INTO seen VALUES (?, ?, ?, ?, ?, ?)",
    (task["id"], task["etag"], task["listId"], int(time.time()), session_id, "dispatched")
)
conn.commit()
```

### 8. Summary
Print: `Cycle complete: {N} found, {dispatched} dispatched, {skipped} skipped, {already_seen} already seen.`

---

## `/driver-status` command

1. Query `state/seen.sqlite` for the 20 most recently dispatched rows.
2. Run `python3 .claude/skills/orchapi-client/client.py list-sessions --status running --limit 20` and `--status queued --limit 20`.
3. Print a formatted table: task_id (truncated), dispatched_at, session_id, current orchapi status.

---

## `/writeback-loop` command

Runs the writeback worker in the foreground. Subscribes to the orchapi SSE
stream and PATCHes Microsoft Graph (To-Do + Planner) when sessions complete.

```bash
python3 .claude/skills/todo-writeback/writeback.py
```

Requires `state/token_cache.bin` with `Tasks.ReadWrite` + `Group.ReadWrite.All`
scopes. Re-run `python3 .claude/skills/todo-poll/poll.py --login` once to
re-consent if you haven't already.

---

## Configuration files

| File | Purpose |
|------|---------|
| `config/driver.toml` | cadence, orchapi URL, msal settings, max_in_flight |
| `config/routes.toml` | routing rules (copy from `routes.toml.example`) |
| `state/seen.sqlite` | dedupe store (auto-created) |
| `state/token_cache.bin` | msal token cache (created by `--login`) |

---

## Error principles

- Auth failure in poll → abort cycle, remind user to `--login`.
- orchapi unreachable → abort cycle with clear message.
- Single task dispatch failure → log + continue.
- Never mark a task as seen unless its session was successfully created.
