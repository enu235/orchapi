#!/usr/bin/env python3
"""Route a Microsoft To-Do task to an orchapi session configuration.

Reads task JSON from stdin (or a file path argument).
Outputs one JSON line:
  {"profile": "...", "cwd": "...", "overrides": {}, "source": "...", "planner": ...}
                                                                    matched rule
  {"action": "skip"}                                                explicitly skipped
  {"action": "llm_fallback"}                                        no rule matched
"""

import json
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        sys.exit("Missing dependency: pip install tomli")

DRIVER_ROOT = Path(__file__).resolve().parents[3]
ROUTES_PATH = DRIVER_ROOT / "config" / "routes.toml"


def load_routes() -> tuple[list, dict]:
    if not ROUTES_PATH.exists():
        return [], {}
    with open(ROUTES_PATH, "rb") as f:
        data = tomllib.load(f)
    return data.get("routes", []), data.get("default", {})


def route(task: dict, rules: list, default: dict) -> dict:
    list_name = task.get("listName", "")
    title = task.get("title", "")
    source = task.get("source", "todo")
    planner = task.get("planner")

    for rule in rules:
        if "list" in rule and rule["list"].lower() != list_name.lower():
            continue
        if "title_match" in rule and not re.search(rule["title_match"], title):
            continue
        if "source" in rule and rule["source"] != source:
            continue
        return {
            "profile": rule.get("profile", default.get("fallback_profile", "example")),
            "cwd": rule.get("cwd", default.get("fallback_cwd", "/tmp")),
            "overrides": rule.get("overrides", {}),
            "source": source,
            "planner": planner,
        }

    action = default.get("unmatched_action", "llm_fallback")
    if action == "skip":
        return {"action": "skip"}
    if action == "default_profile":
        return {
            "profile": default.get("fallback_profile", "example"),
            "cwd": default.get("fallback_cwd", "/tmp"),
            "overrides": {},
            "source": source,
            "planner": planner,
        }
    return {"action": "llm_fallback"}


if __name__ == "__main__":
    if len(sys.argv) > 1:
        task = json.loads(Path(sys.argv[1]).read_text())
    else:
        task = json.loads(sys.stdin.read())

    rules, default = load_routes()
    print(json.dumps(route(task, rules, default)))
