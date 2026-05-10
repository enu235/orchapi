#!/usr/bin/env python3
"""Writeback worker: SSE-driven Microsoft Graph PATCH dispatcher.

Subscribes to orchapi's writeback SSE stream and, for each completed session
that carries an external_task, claims the writeback, builds a note from the
session record + events, then PATCHes Microsoft To-Do and (when applicable)
the linked Planner task. A poll-fallback loop runs in parallel to catch
sessions missed by SSE drops.
"""

import json
import sys
import threading
import time
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
    if not CONFIG_PATH.exists():
        sys.exit(f"Config not found: {CONFIG_PATH}")
    with open(CONFIG_PATH, "rb") as f:
        return tomllib.load(f)


# ---------------- HTTP helpers ----------------

def _get_json(url: str) -> object | None:
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            return json.loads(resp.read())
    except Exception as exc:
        print(f"GET {url} failed: {exc}", file=sys.stderr)
        return None


def _post_json(url: str, body: dict) -> dict | None:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read()
            if not raw:
                return {"ok": True}
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        print(f"POST {url} -> HTTP {exc.code}: {exc.read().decode(errors='replace')}", file=sys.stderr)
        return None
    except Exception as exc:
        print(f"POST {url} failed: {exc}", file=sys.stderr)
        return None


def _graph_get_timeout(token: str, url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def _graph_patch(url: str, body: dict, etag: str, token: str) -> bytes:
    data = json.dumps(body).encode()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "If-Match": etag,
    }
    req = urllib.request.Request(url, data=data, headers=headers, method="PATCH")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read()
    except urllib.error.HTTPError as exc:
        if exc.code == 412:
            fresh = _graph_get_timeout(token, url)
            fresh_etag = fresh.get("@odata.etag", etag)
            headers["If-Match"] = fresh_etag
            req2 = urllib.request.Request(url, data=data, headers=headers, method="PATCH")
            with urllib.request.urlopen(req2, timeout=10) as resp2:
                return resp2.read()
        raise


# ---------------- Graph PATCH builders ----------------

def _patch_todo(external_task: dict, status: str, note: str, token: str) -> None:
    todo = external_task.get("todo", {})
    list_id = todo.get("list_id") or todo.get("listId", "")
    task_id = todo.get("task_id") or todo.get("taskId", "")
    etag = todo.get("etag", "")
    if not list_id or not task_id:
        raise RuntimeError("missing todo list_id/task_id in external_task")
    url = f"https://graph.microsoft.com/v1.0/me/todo/lists/{list_id}/tasks/{task_id}"
    body: dict = {"body": {"content": note, "contentType": "text"}}
    if status == "success":
        body["status"] = "completed"
    _graph_patch(url, body, etag, token)


def _patch_planner(planner: dict, status: str, note: str, token: str) -> None:
    task_id = planner.get("task_id", "")
    etag = planner.get("etag", "")
    details_etag = planner.get("details_etag", "")
    if not task_id:
        raise RuntimeError("missing planner task_id")

    if status == "success":
        _graph_patch(
            f"https://graph.microsoft.com/v1.0/planner/tasks/{task_id}",
            {"percentComplete": 100},
            etag,
            token,
        )

    details_url = f"https://graph.microsoft.com/v1.0/planner/tasks/{task_id}/details"
    current = _graph_get_timeout(token, details_url)
    existing_desc = current.get("description", "")
    new_desc = (existing_desc + "\n\n" + note).strip()
    fresh_etag = current.get("@odata.etag", details_etag)
    _graph_patch(details_url, {"description": new_desc}, fresh_etag, token)


# ---------------- Session processing ----------------

def process_session(session_id: str, token: str, config: dict) -> None:
    base = config["orchapi"]["base_url"].rstrip("/")

    claim = _post_json(f"{base}/sessions/{session_id}/writeback-claim", {})
    if not claim or not claim.get("ok"):
        return

    session = _get_json(f"{base}/sessions/{session_id}")
    if not isinstance(session, dict):
        return
    external_task = session.get("external_task") or {}
    if not external_task:
        return
    status = session.get("status", "")
    outcome_summary = session.get("outcome_summary") or ""

    events = _get_json(f"{base}/sessions/{session_id}/events") or []
    notes: list[str] = []
    if isinstance(events, list):
        for e in events:
            payload = e.get("payload") if isinstance(e, dict) else None
            if isinstance(payload, dict):
                text = payload.get("text")
                if text:
                    notes.append(text)

    note_lines = [
        f"orchapi session {session_id} — {status}",
        f"Outcome: {outcome_summary}",
    ]
    if notes:
        note_lines.append("Notes:")
        for n in notes:
            note_lines.append(f"  • {n}")
    note_text = "\n".join(note_lines)

    refreshed_etags: dict[str, str] = {}
    error: str | None = None
    try:
        _patch_todo(external_task, status, note_text, token)
        refreshed_etags["todo"] = "refreshed"
        if external_task.get("planner"):
            _patch_planner(external_task["planner"], status, note_text, token)
            refreshed_etags["planner"] = "refreshed"
    except Exception as exc:
        error = str(exc)
        print(f"Writeback {session_id}: PATCH failed: {exc}", file=sys.stderr)

    ack_body: dict = {"result": "failed" if error else "done"}
    if error:
        ack_body["error"] = error
    if refreshed_etags:
        ack_body["refreshed_etags"] = refreshed_etags
    _post_json(f"{base}/sessions/{session_id}/writeback-ack", ack_body)
    print(f"writeback {session_id} -> {ack_body['result']}")


# ---------------- Loops ----------------

def _sse_loop(config: dict, token: str) -> None:
    url = config["writeback"]["stream_url"]
    while True:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=300) as resp:
                for raw_line in resp:
                    line = raw_line.decode().strip()
                    if line.startswith("data:"):
                        try:
                            payload = json.loads(line[5:].strip())
                        except json.JSONDecodeError:
                            continue
                        sid = payload.get("session_id")
                        if sid:
                            try:
                                process_session(sid, token, config)
                            except Exception as exc:
                                print(f"process_session({sid}) errored: {exc}", file=sys.stderr)
        except Exception as exc:
            print(f"SSE error: {exc}, reconnecting in 10s", file=sys.stderr)
            time.sleep(10)


def _poll_loop(config: dict, token: str) -> None:
    base = config["orchapi"]["base_url"].rstrip("/")
    interval = int(config.get("writeback", {}).get("poll_fallback_seconds", 60))
    while True:
        try:
            pending = _get_json(f"{base}/sessions?writeback_status=pending&limit=50")
            if isinstance(pending, list):
                for s in pending:
                    sid = s.get("id") if isinstance(s, dict) else None
                    if sid:
                        try:
                            process_session(sid, token, config)
                        except Exception as exc:
                            print(f"poll process_session({sid}) errored: {exc}", file=sys.stderr)
        except Exception as exc:
            print(f"poll loop error: {exc}", file=sys.stderr)
        time.sleep(interval)


def main() -> None:
    config = load_config()
    if not config.get("writeback", {}).get("enabled", True):
        print("writeback disabled in driver.toml; exiting", file=sys.stderr)
        return

    token = _get_token(config.get("graph", {}), force_login=False)

    sse = threading.Thread(target=_sse_loop, args=(config, token), daemon=True)
    poll = threading.Thread(target=_poll_loop, args=(config, token), daemon=True)
    sse.start()
    poll.start()
    print("writeback worker started (SSE + poll fallback)", file=sys.stderr)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("shutting down", file=sys.stderr)


if __name__ == "__main__":
    main()
