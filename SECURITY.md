# Security Policy

## Reporting a vulnerability

Please **do not** file public GitHub issues for security vulnerabilities.

Use [GitHub private security advisories](https://github.com/enu235/orchapi/security/advisories/new) to report vulnerabilities confidentially. We aim to acknowledge reports within 48 hours and to publish a fix or mitigation within 14 days for confirmed issues.

---

## Supported versions

Only the latest commit on `main` receives security fixes. Pin to a specific release tag if you need a stable version.

---

## Threat model and scope of concern

| Area | Risk level | Notes |
|---|---|---|
| Network exposure | Low by default | orchapi binds to `127.0.0.1:7878` and sets CORS to permissive for localhost tooling. Changing `bind` to `0.0.0.0` exposes the API to your local network with **no authentication** — do not do this on untrusted networks. |
| Agent CLI permissions | Medium | The primary attack surface. Agent CLIs (`claude`, `copilot`, `codex`) run with the OS permissions of the `orchapi` process. A malicious `action_prompt` could instruct the agent to read or modify files accessible to that user. Use `allowed_tools` and `disallowed_tools` in profiles to constrain what each session may do. |
| Microsoft Graph token cache | Medium | `driver/state/token_cache.bin` holds a refresh token scoped to `Tasks.ReadWrite` and `Group.ReadWrite.All`. This file is gitignored and should never be committed or shared. Protect it with appropriate filesystem permissions (`chmod 600`). |
| SQLite session database | Low | `.orchapi/orchapi.db` may contain `action_prompt` text and `outcome_summary` values that include task content from To-Do / Planner. The directory is gitignored. Restrict read access if session content is sensitive. |
| Session log files | Low | `.orchapi/logs/` contains raw stdout/stderr from agent processes, which may include secrets printed by the agent during a session. The directory is gitignored. |
| Dependency supply chain | Low-Medium | The Rust dependency tree is locked in `Cargo.lock`. Run `cargo audit` periodically. Python driver dependencies are minimal (`msal`, `tomli`). |
| Dashboard (`/ui`) | Low | The embedded dashboard is a static HTML page served only from localhost. It makes requests to the same origin. There is no authentication on the dashboard or the REST API. |

---

## Out of scope

- Vulnerabilities in `claude`, `copilot`, or `codex` themselves — report these to their respective vendors.
- Issues that require an attacker already having shell access to the machine running orchapi — local privilege escalation is out of scope for a localhost-only tool.
- Social-engineering or phishing attacks.

---

## Hardening recommendations

1. Keep `bind = "127.0.0.1:7878"` in `config.toml`. Never expose the API to the internet.
2. Run orchapi as a dedicated low-privilege user account, not as your primary user or root.
3. Set `allowed_tools` in each profile to the minimum set of tools the agent needs.
4. Rotate your Microsoft Graph token periodically: delete `driver/state/token_cache.bin` and re-run `python3 .claude/skills/todo-poll/poll.py --login`.
5. Review agent session logs in `.orchapi/logs/` for unexpected file access or network activity.
