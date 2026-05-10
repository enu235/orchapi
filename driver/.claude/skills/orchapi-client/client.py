#!/usr/bin/env python3
"""Thin wrapper around the orchapi REST API.

Commands:
  list-profiles
  create-session --spec '<json>'
  get-session <id>
  list-sessions [--status <s>] [--limit <n>]
  count-running
  post-event --session <id> --kind <k> [--text <t>] [--percent-complete <n>]
  ack-writeback --session <id> --result <done|failed> [--error <e>]
  list-pending-writeback [--limit <n>]
"""

import argparse
import json
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

DRIVER_ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = DRIVER_ROOT / "config" / "driver.toml"


def base_url() -> str:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH, "rb") as f:
            cfg = tomllib.load(f)
        return cfg.get("orchapi", {}).get("base_url", "http://127.0.0.1:7878").rstrip("/")
    return "http://127.0.0.1:7878"


def _get(path: str) -> object:
    url = base_url() + path
    try:
        with urllib.request.urlopen(url) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        sys.exit(f"GET {path} failed ({exc.code}): {exc.read().decode()}")
    except urllib.error.URLError as exc:
        sys.exit(f"Cannot reach orchapi at {url}: {exc.reason}")


def _post(path: str, body: dict) -> object:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        base_url() + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            if not raw:
                return {"ok": True}
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        sys.exit(f"POST {path} failed ({exc.code}): {exc.read().decode()}")
    except urllib.error.URLError as exc:
        sys.exit(f"Cannot reach orchapi: {exc.reason}")


def _post_no_resp(path: str, body: dict) -> tuple[bool, dict]:
    """POST without exiting on error. Returns (ok, parsed_body_or_error_info)."""
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        base_url() + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            if not raw:
                return True, {"ok": True}
            return True, json.loads(raw)
    except urllib.error.HTTPError as exc:
        try:
            body_text = exc.read().decode()
        except Exception:
            body_text = ""
        return False, {"status": exc.code, "body": body_text}
    except urllib.error.URLError as exc:
        return False, {"error": str(exc.reason)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list-profiles")

    cs = sub.add_parser("create-session")
    cs.add_argument("--spec", required=True, help="JSON session spec")

    gs = sub.add_parser("get-session")
    gs.add_argument("id")

    ls = sub.add_parser("list-sessions")
    ls.add_argument("--status")
    ls.add_argument("--limit", type=int, default=50)

    sub.add_parser("count-running")

    pe = sub.add_parser("post-event")
    pe.add_argument("--session", required=True)
    pe.add_argument("--kind", required=True)
    pe.add_argument("--text")
    pe.add_argument("--percent-complete", type=int)

    aw = sub.add_parser("ack-writeback")
    aw.add_argument("--session", required=True)
    aw.add_argument("--result", required=True, choices=["done", "failed"])
    aw.add_argument("--error")

    lpw = sub.add_parser("list-pending-writeback")
    lpw.add_argument("--limit", type=int, default=50)

    args = parser.parse_args()

    if args.cmd == "list-profiles":
        print(json.dumps(_get("/profiles"), indent=2))

    elif args.cmd == "create-session":
        spec = json.loads(args.spec)
        resp = _post("/sessions", spec)
        print(json.dumps(resp))

    elif args.cmd == "get-session":
        print(json.dumps(_get(f"/sessions/{args.id}"), indent=2))

    elif args.cmd == "list-sessions":
        path = f"/sessions?limit={args.limit}"
        if args.status:
            path += f"&status={args.status}"
        print(json.dumps(_get(path), indent=2))

    elif args.cmd == "count-running":
        running = _get("/sessions?status=running&limit=500")
        queued = _get("/sessions?status=queued&limit=500")
        assert isinstance(running, list)
        assert isinstance(queued, list)
        print(len(running) + len(queued))

    elif args.cmd == "post-event":
        body: dict = {"kind": args.kind}
        if args.text is not None:
            body["text"] = args.text
        if args.percent_complete is not None:
            body["percent_complete"] = args.percent_complete
        ok, resp = _post_no_resp(f"/sessions/{args.session}/events", body)
        print(json.dumps({"ok": ok, "response": resp}))

    elif args.cmd == "ack-writeback":
        body = {"result": args.result}
        if args.error:
            body["error"] = args.error
        ok, resp = _post_no_resp(f"/sessions/{args.session}/writeback-ack", body)
        print(json.dumps({"ok": ok, "response": resp}))

    elif args.cmd == "list-pending-writeback":
        print(json.dumps(_get(f"/sessions?writeback_status=pending&limit={args.limit}"), indent=2))


if __name__ == "__main__":
    main()
