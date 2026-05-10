# Contributing to orchapi

Thank you for your interest in contributing. This document covers the repo layout, how to get a dev environment running, how to extend the system, and the conventions we use for pull requests.

---

## Repo layout

```
orchapi/
├── src/
│   ├── main.rs          # Axum router, CLI args, server startup
│   ├── manager.rs       # Session lifecycle, concurrency semaphores, writeback broadcast
│   ├── spec.rs          # SessionSpec types and resolve_spec() merge logic
│   ├── store.rs         # SQLite pool, all queries, migration runner
│   ├── config.rs        # AppConfig, ProfileStore, Profile types
│   ├── log_writer.rs    # Per-session log file management
│   ├── outcome.rs       # Outcome type (success/failed/timeout) and helpers
│   ├── adapters/        # Agent CLI adapters (one file per agent)
│   └── api/             # Axum handler modules (sessions, profiles, writeback, ui)
├── profiles/            # TOML profile files loaded at startup
├── migrations/          # SQLite schema migrations (numbered, append-only)
├── assets/
│   └── index.html       # Embedded dashboard SPA
├── driver/              # Python driver workspace
│   ├── config/          # driver.toml, routes.toml (copy from .example files)
│   ├── state/           # Runtime state — gitignored
│   └── .claude/         # Claude Code project: CLAUDE.md, skills, agents, commands
├── config.toml.example  # Annotated server config template
└── Cargo.toml
```

---

## Dev environment setup

### Server (Rust)

```bash
git clone https://github.com/enu235/orchapi.git
cd orchapi

# Run in dev mode (auto-recompile is not built-in; use cargo-watch if you want it)
cargo run -- --config config.toml

# Run tests
cargo test

# Check formatting and lints before committing
cargo fmt --check
cargo clippy -- -D warnings
```

The server writes to `.orchapi/` in the current directory. This directory is gitignored. You can wipe it between test runs without consequence (sessions are lost, but the schema is re-created on next startup).

### Driver — Claude Code

```bash
cd driver
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Authenticate once (shared between all driver CLIs)
python3 .claude/skills/todo-poll/poll.py --login

# Open the driver in Claude Code
claude --cwd .
```

Inside that Claude Code session the slash commands `/poll-todos`, `/driver-status`, and `/writeback-loop` are available.

### Driver — GitHub Copilot CLI

The Copilot driver shares all skills, config, and state with the Claude driver. After completing the auth step above:

```bash
cd driver

# One-shot poll cycle
copilot -p "/poll-todos" -s --allow-all-tools

# Status check
copilot -p "/driver-status" -s --allow-all-tools
```

Prompts live in `driver/.github/prompts/`. When modifying the poll cycle, update both `driver/.claude/CLAUDE.md` (canonical) and `driver/.github/prompts/poll-todos.prompt.md` (Copilot translation) to keep them in sync. Skills in `driver/.claude/skills/*.py` are shared — never duplicate them into `.github/skills/`.

### Useful environment variables

| Variable | Default | Description |
|---|---|---|
| `ORCHAPI_CONFIG` | `config.toml` | Path to the server config file |
| `RUST_LOG` | `info` | Log level (`trace`, `debug`, `info`, `warn`, `error`) |

---

## Testing the server locally with curl

```bash
# Health check
curl http://127.0.0.1:7878/healthz

# List profiles
curl http://127.0.0.1:7878/profiles

# Create a session (requires claude on PATH)
curl -s -X POST http://127.0.0.1:7878/sessions \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "claude",
    "profile": "default",
    "overrides": {
      "action_prompt": "Print the current date and exit.",
      "cwd": "/tmp"
    }
  }' | jq .

# Get session status (replace SESSION_ID)
curl http://127.0.0.1:7878/sessions/SESSION_ID

# Stream live output (SSE — stays open until session ends)
curl -N http://127.0.0.1:7878/sessions/SESSION_ID/stream

# Fetch completed log
curl http://127.0.0.1:7878/sessions/SESSION_ID/logs

# Cancel a running session
curl -X POST http://127.0.0.1:7878/sessions/SESSION_ID/cancel

# Open the dashboard
open http://127.0.0.1:7878/ui
```

---

## How to add a new agent adapter

Each agent is a struct that implements the `AgentAdapter` trait defined in `src/adapters/mod.rs`:

```rust
pub trait AgentAdapter: Send + Sync {
    fn kind(&self) -> AgentKind;
    fn build_command(&self, spec: &SessionSpec) -> Result<Command>;
    fn extract_outcome(&self, log: &str, exit_code: i32) -> Outcome;
}
```

Steps:

1. Add a variant to the `AgentKind` enum in `src/spec.rs` (e.g. `Gemini`).
2. Create `src/adapters/gemini.rs`. Implement `AgentAdapter`:
   - `build_command` — construct a `tokio::process::Command` from the `SessionSpec` fields (model, allowed_tools, cwd, etc.).
   - `extract_outcome` — inspect the captured log and exit code; return `Outcome::Success`, `Outcome::Failed`, or `Outcome::Timeout`.
3. Register the adapter in `src/adapters/mod.rs`:
   ```rust
   mod gemini;
   pub use gemini::GeminiAdapter;
   // ...
   AgentKind::Gemini => Box::new(GeminiAdapter),
   ```
4. Add any agent-specific defaults struct to `src/config.rs` and wire it into `AppConfig` and `resolve_spec` in `src/spec.rs`.
5. Add a `[defaults.gemini]` section to `config.toml.example`.

Keep adapters thin. All concurrency, logging, state, and cancellation logic lives in `src/manager.rs`.

---

## How to add a new profile

Drop a TOML file into the `profiles/` directory. Profiles are loaded at startup; the filename (without `.toml`) becomes the profile name.

Minimum viable profile:

```toml
# profiles/my-profile.toml
agent = "claude"
system_prompt = """
You are a specialist for X. Do Y and nothing else.
"""

[overrides]
allowed_tools = ["Read", "Edit", "Bash"]
max_turns = 30
```

All fields are optional. See `profiles/example.toml` and `profiles/bug-fixer.toml` for working examples. See `src/config.rs` (`ProfileOverrides`) for the full list of supported keys.

Profile values are merged at request time: `config.toml` defaults < profile file < per-request overrides. There is no need to restart the server to pick up profile changes — they are re-read on each request (if you want hot-reload; otherwise restart the server).

---

## PR conventions

- **Branch naming:** `feat/short-description`, `fix/short-description`, `docs/short-description`.
- **Commit messages:** imperative mood, present tense. First line ≤ 72 characters. Example: `Add Gemini adapter with gemini-2.0-flash support`.
- **One concern per PR.** Refactors and feature additions in separate PRs.
- **Rust code:** must pass `cargo fmt` and `cargo clippy -- -D warnings` with no new warnings.
- **Python code:** PEP 8. No new dependencies unless genuinely necessary; add them to `requirements.txt` with a pinned major version.
- **Tests:** add or update unit tests for non-trivial logic. The adapter's `extract_outcome` function and any new routing logic are good candidates.
- **CHANGELOG:** not required for minor fixes; appreciated for new features.

---

## Filing issues

Use [GitHub Issues](https://github.com/enu235/orchapi/issues).

- **Bug reports:** include the orchapi version (`orchapi --version`), OS, Rust version (`rustc --version`), the request you made, and the relevant log output (`RUST_LOG=debug orchapi 2>&1 | head -100`).
- **Feature requests:** describe the problem you are trying to solve before proposing a solution.
- **Security vulnerabilities:** do **not** file a public issue. See [SECURITY.md](SECURITY.md).
