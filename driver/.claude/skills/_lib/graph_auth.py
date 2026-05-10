"""Shared MSAL device-code auth helper for Microsoft Graph.

Used by skills that need a Graph access token (todo-poll, todo-writeback).
Token cache lives at the path declared by `[graph].token_cache_path` in
`config/driver.toml`, relative to the driver root.
"""

import sys
from pathlib import Path

try:
    import msal
except ImportError:
    sys.exit("Missing dependency: pip install msal")

DRIVER_ROOT = Path(__file__).resolve().parents[3]


def get_token(g: dict, force_login: bool = False) -> str:
    client_id = g.get("client_id", "14d82eec-204b-4c2f-b7e8-296a70dab67e")
    tenant = g.get("tenant", "common")
    scopes = g.get("scopes", ["Tasks.Read"])
    cache_path = DRIVER_ROOT / g.get("token_cache_path", "state/token_cache.bin").lstrip("./")

    cache = msal.SerializableTokenCache()
    if cache_path.exists() and not force_login:
        cache.deserialize(cache_path.read_text())

    app = msal.PublicClientApplication(
        client_id,
        authority=f"https://login.microsoftonline.com/{tenant}",
        token_cache=cache,
    )

    accounts = app.get_accounts()
    result = None
    if accounts and not force_login:
        result = app.acquire_token_silent(scopes, account=accounts[0])

    if not result:
        flow = app.initiate_device_flow(scopes=scopes)
        if "user_code" not in flow:
            sys.exit(f"Device flow failed: {flow.get('error_description', flow)}")
        print(flow["message"], file=sys.stderr)
        result = app.acquire_token_by_device_flow(flow)

    if "error" in result:
        sys.exit(f"Auth error: {result.get('error_description', result['error'])}")

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(cache.serialize())
    return result["access_token"]
