# orchapi driver

A Claude Code workspace that polls Microsoft To-Do, maps tasks to orchapi session profiles, and dispatches them automatically. Replaces the manual PowerShell → orchapi workflow.

## Prerequisites

- Python 3.11+ (or 3.10 with `tomli`)
- `pip install -r requirements.txt`
- orchapi running at `http://127.0.0.1:7878` (`cd .. && cargo run`)
- Microsoft account with To-Do tasks

## First-time setup

### 1. Install dependencies

```bash
cd /Users/allan/dev/orchapi/driver
pip install -r requirements.txt
```

### 2. Authenticate with Microsoft Graph

```bash
python3 .claude/skills/todo-poll/poll.py --login
```

Follow the device-code prompt (open a browser, enter the code shown). Your token is cached at `state/token_cache.bin` for future runs. Subsequent polls are silent.

### 3. Configure routes

```bash
cp config/routes.toml.example config/routes.toml
```

Edit `config/routes.toml` to map your To-Do list names or task title patterns to orchapi profiles. Unmatched tasks are either skipped or routed by the LLM fallback (controlled by `[default] unmatched_action`).

### 4. Verify the poll

```bash
python3 .claude/skills/todo-poll/poll.py | head -40
```

Should print a JSON array of your pending tasks.

## Running the driver

Open Claude Code in this directory:

```bash
claude --cwd /Users/allan/dev/orchapi/driver
```

Run a single cycle:
```
/poll-todos
```

Start the recurring loop (every 5 minutes):
```
/loop 5m /poll-todos
```

Check recent dispatches:
```
/driver-status
```

## Switching to PowerShell mode

If `msal` device-code auth fails (e.g. your tenant blocks the well-known client ID), switch to PowerShell mode:

1. In `config/driver.toml`, set `mode = "powershell"`.
2. Add a `-Json` switch to `Get-PendingTodos.ps1` — append the following param and output block:

```powershell
# In the param block, add:
[switch]$Json

# Replace the final if/else block with:
if ($Raw -or $Json) {
    if ($Json) {
        $fields = $rawItems | ForEach-Object {
            [pscustomobject]@{
                id             = $_.id           # requires adding $_.id to $rows above
                listId         = $_.listId
                listName       = $_.listName
                title          = $_.title
                body           = $_.body
                due            = $_.due
                importance     = $_.importance
                status         = $_.status
                etag           = $_.'@odata.etag'
                lastModified   = $_.lastModifiedDateTime
            }
        }
        $fields | ConvertTo-Json -Depth 5
    } else {
        $rawItems
    }
}
```

## Configuration reference

### `config/driver.toml`

| Key | Default | Description |
|-----|---------|-------------|
| `poll.dedupe_ttl_hours` | `168` | Forget seen tasks after N hours (0 = never) |
| `orchapi.base_url` | `http://127.0.0.1:7878` | orchapi server URL |
| `orchapi.max_in_flight` | `4` | Skip dispatch if this many sessions are running + queued |
| `graph.mode` | `msal` | `msal` or `powershell` |
| `graph.client_id` | well-known Graph app | Entra app client ID |
| `graph.tenant` | `common` | `common`, `consumers`, or your tenant ID |
| `graph.token_cache_path` | `./state/token_cache.bin` | msal token cache location |

### `config/routes.toml`

Copy from `routes.toml.example`. Rules match on `list` (exact, case-insensitive) and/or `title_match` (Python regex). First match wins.
