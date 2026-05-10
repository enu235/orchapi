#!/usr/bin/env python3
"""Poll Microsoft To-Do via MS Graph. Emits a JSON array to stdout.

Two modes, selected by [graph] mode in config/driver.toml:
  msal        — native device-code auth, token cached at state/token_cache.bin
  powershell  — delegates to Get-PendingTodos.ps1 -Raw -Json (see README for PS1 patch)

When a task is linked to a Microsoft Planner task (via linkedResources), this
poller fetches the Planner task + details and emits a `planner` block plus
`source: "planner"`.
"""

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        sys.exit("Missing dependency: pip install tomli")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from _lib.graph_auth import get_token as _get_token  # noqa: E402

DRIVER_ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = DRIVER_ROOT / "config" / "driver.toml"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH, "rb") as f:
            return tomllib.load(f)
    return {}


def _graph_get(token: str, url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def _graph_get_timeout(token: str, url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())


def _all_pages(token: str, url: str) -> list:
    items: list = []
    while url:
        data = _graph_get(token, url)
        items.extend(data.get("value", []))
        url = data.get("@odata.nextLink", "")
    return items


def _find_planner_link(linked_resources: list) -> dict | None:
    for lr in linked_resources:
        if lr.get("applicationName") == "Microsoft Planner":
            return lr
    return None


def _fetch_planner_context(token: str, planner_task_id: str) -> dict | None:
    """Returns planner enrichment dict or None on error."""
    try:
        task = _graph_get_timeout(
            token, f"https://graph.microsoft.com/v1.0/planner/tasks/{planner_task_id}"
        )
        details = _graph_get_timeout(
            token,
            f"https://graph.microsoft.com/v1.0/planner/tasks/{planner_task_id}/details",
        )
        assignments = list(task.get("assignments", {}).keys())
        checklist = [
            {"id": k, "title": v.get("title", ""), "isChecked": v.get("isChecked", False)}
            for k, v in details.get("checklist", {}).items()
        ]
        return {
            "task_id": planner_task_id,
            "etag": task.get("@odata.etag", ""),
            "plan_id": task.get("planId", ""),
            "bucket_id": task.get("bucketId", ""),
            "percent_complete": task.get("percentComplete", 0),
            "priority": task.get("priority", 5),
            "assignments": assignments,
            "details_etag": details.get("@odata.etag", ""),
            "description": details.get("description", ""),
            "checklist": checklist,
            "web_url": "",
        }
    except Exception as exc:
        print(f"Warning: Planner fetch for {planner_task_id}: {exc}", file=sys.stderr)
        return None


def _poll_msal(g: dict, force_login: bool) -> list:
    token = _get_token(g, force_login)
    lists = _all_pages(token, "https://graph.microsoft.com/v1.0/me/todo/lists?$top=100")
    tasks: list = []
    encoded_filter = "status%20ne%20'completed'"
    select = "id,title,body,dueDateTime,importance,status,lastModifiedDateTime"
    for lst in lists:
        url = (
            f"https://graph.microsoft.com/v1.0/me/todo/lists/{lst['id']}/tasks"
            f"?$filter={encoded_filter}&$top=100&$select={select}&$expand=linkedResources"
        )
        try:
            raw = _all_pages(token, url)
        except Exception as exc:
            print(f"Warning: list '{lst.get('displayName')}': {exc}", file=sys.stderr)
            continue
        for t in raw:
            linked = t.get("linkedResources") or []
            planner_link = _find_planner_link(linked)
            planner_ctx = None
            if planner_link:
                pid = planner_link.get("externalId")
                if pid:
                    planner_ctx = _fetch_planner_context(token, pid)
                    if planner_ctx:
                        planner_ctx["web_url"] = planner_link.get("webUrl", "")

            tasks.append({
                "id": t["id"],
                "listId": lst["id"],
                "listName": lst.get("displayName", ""),
                "title": t.get("title", ""),
                "body": (t.get("body") or {}).get("content", ""),
                "due": (t.get("dueDateTime") or {}).get("dateTime"),
                "importance": t.get("importance", "normal"),
                "status": t.get("status", "notStarted"),
                "etag": t.get("@odata.etag", ""),
                "lastModified": t.get("lastModifiedDateTime"),
                "source": "planner" if planner_ctx else "todo",
                "planner": planner_ctx,
            })
    return tasks


def _poll_powershell(g: dict) -> list:
    script_rel = g.get("pwsh_script", "../Get-PendingTodos.ps1")
    script = (DRIVER_ROOT / script_rel).resolve()
    if not script.exists():
        sys.exit(f"PowerShell script not found: {script}")
    result = subprocess.run(
        ["pwsh", "-NoLogo", "-NonInteractive", "-File", str(script), "-Raw", "-Json"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"PowerShell error:\n{result.stderr}")
    return json.loads(result.stdout)


def poll(cfg: dict, force_login: bool = False) -> list:
    g = cfg.get("graph", {})
    mode = g.get("mode", "msal")
    if mode == "powershell":
        return _poll_powershell(g)
    return _poll_msal(g, force_login)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--login", action="store_true", help="Force device-code re-auth")
    args = parser.parse_args()

    tasks = poll(load_config(), force_login=args.login)
    print(json.dumps(tasks, indent=2, ensure_ascii=False))
