# Installation Reference

---

## Prerequisites

| Requirement | Minimum version | Required | Install hint |
|---|---|---|---|
| Rust toolchain (`rustc` + `cargo`) | 1.75 | Yes | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Python | 3.10 | Yes | `brew install python@3.12` (macOS) / `sudo apt install python3` (Debian) |
| `claude` CLI | any | Yes (for Claude sessions) | `npm install -g @anthropic-ai/claude-code` |
| `copilot` CLI | any | Optional | `gh extension install github/gh-copilot` (standalone binary expected) |
| `codex` CLI | any | Optional | `npm install -g @openai/codex` |
| PowerShell 7+ (`pwsh`) | 7.0 | Optional | Only needed for PowerShell polling mode |

You only need the agent CLIs you intend to dispatch to. At minimum, install `claude`.

---

## One-line install

### macOS / Linux

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh
```

### Windows (PowerShell 7+)

```powershell
iwr -useb https://raw.githubusercontent.com/enu235/orchapi/main/install.ps1 | iex
```

The installer clones the repository to `~/.local/share/orchapi` (macOS/Linux) or `%LOCALAPPDATA%\orchapi` (Windows), builds the binary, creates a Python venv, and writes a launcher to `~/.local/bin/orchapi`.

---

## Installer flags

All flags work with both the curl-piped form (`| sh -s -- <flags>`) and the direct form (`./install.sh <flags>`).

| Flag | Description | Example |
|---|---|---|
| `--prefix <dir>` | Install to a custom root directory instead of the default (`~/.local/share/orchapi`). The directory is created if it does not exist. | `--prefix /opt/orchapi` |
| `--check-only` | Print the status of all dependencies (found / version / install hint) and exit without installing anything. | (no argument) |
| `--no-build` | Skip `cargo build --release`. Useful if you have a pre-built binary or want to build separately. Config scaffolding and the launcher are still written. | (no argument) |
| `--upgrade` | `git pull --ff-only` in the existing clone, then rebuild and refresh the Python venv. Does not re-clone. | (no argument) |
| `--uninstall` | Remove the launcher (`~/.local/bin/orchapi`) and the Python venv (`driver/.venv`). Prints a note about manually removing the repo directory. | (no argument) |

### Examples

Check dependencies without installing:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --check-only
```

Install to a custom directory:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --prefix /opt/orchapi
```

Upgrade an existing installation:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --upgrade
```

Uninstall:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --uninstall
```

---

## What the installer produces

After a successful install, the file layout at the install root (`~/.local/share/orchapi` by default):

```
~/.local/share/orchapi/          ← PREFIX (the install root)
├── target/
│   └── release/
│       └── orchapi              ← compiled server binary
├── src/                         ← Rust source
├── profiles/                    ← session profile TOML templates
├── config.toml                  ← server configuration (copied from .example)
├── config.toml.example          ← annotated template
├── migrations/                  ← SQLite schema migrations
├── assets/                      ← embedded dashboard SPA
├── driver/
│   ├── .venv/                   ← Python virtualenv
│   ├── .claude/                 ← Claude Code workspace (commands, skills, agents)
│   ├── config/
│   │   ├── driver.toml          ← driver configuration (copied from .example)
│   │   ├── driver.toml.example
│   │   └── routes.toml          ← routing rules (copied from .example)
│   ├── state/                   ← runtime state (gitignored)
│   │   └── .gitkeep
│   └── requirements.txt
├── INSTALL.md
└── README.md

~/.local/bin/
└── orchapi                      ← launcher script (cd PREFIX && exec binary "$@")
```

Runtime data (created on first run, gitignored):

```
~/.local/share/orchapi/
├── .orchapi/
│   ├── orchapi.db               ← SQLite session database
│   └── logs/
│       └── YYYY/MM/DD/
│           └── <session-id>.log ← per-session agent output
└── driver/state/
    ├── seen.sqlite              ← driver deduplication database
    └── token_cache.bin          ← MSAL token cache
```

---

## Platform notes

### macOS

- Xcode Command Line Tools are required by Cargo: `xcode-select --install`.
- Homebrew is not required but is the easiest way to install Python: `brew install python@3.12`.
- The default install path is `~/.local/share/orchapi`. The launcher is written to `~/.local/bin/orchapi`; add `~/.local/bin` to your `PATH` if it is not already there.
- The server's `data_dir` defaults to `./.orchapi` relative to where you run `orchapi`. The launcher `cd`s to the install root before exec-ing the binary, so logs land in `~/.local/share/orchapi/.orchapi/`.

### Linux

- Any distro with glibc 2.17+ should work.
- Debian/Ubuntu: install build tools before `cargo build`: `sudo apt install build-essential pkg-config libssl-dev`.
- Fedora/RHEL: `sudo dnf install gcc openssl-devel`.
- The default install path and launcher location are the same as macOS.

### Windows

- PowerShell 7+ is required for the install script (`install.ps1`).
- The Rust toolchain requires either Visual Studio Build Tools (MSVC) or the GNU toolchain (`rustup` will guide you).
- Default install path: `%LOCALAPPDATA%\orchapi` (e.g. `C:\Users\You\AppData\Local\orchapi`).
- The launcher is written to `%LOCALAPPDATA%\Microsoft\WindowsApps\orchapi.cmd` — this location is usually on PATH.
- Use forward slashes or double backslashes in TOML path values: `cwd = "C:/Users/You/dev"`.
- The `cancel_grace_seconds` setting uses `CTRL_C_EVENT` instead of SIGTERM/SIGKILL.
- WSL2 is fully supported and behaves identically to Linux.
- winget does not yet have an orchapi package. Use the PowerShell one-liner above.

---

## Manual install steps

For those who prefer not to run a shell script from the internet:

```bash
# 1. Clone the repository
git clone https://github.com/enu235/orchapi.git
cd orchapi

# 2. Verify prerequisites
rustc --version   # need >= 1.75
python3 --version # need >= 3.10

# 3. Build the server binary
cargo build --release
# binary at: target/release/orchapi

# 4. (Optional) Put the binary on your PATH
#    The server reads profiles/ relative to its cwd, so either:
#    a) Always run from the repo root: ./target/release/orchapi
#    b) Use the launcher pattern (cd to repo root, then exec):
mkdir -p ~/.local/bin
cat > ~/.local/bin/orchapi <<'EOF'
#!/usr/bin/env bash
cd /path/to/orchapi
exec ./target/release/orchapi "$@"
EOF
chmod +x ~/.local/bin/orchapi

# 5. Set up Python driver
cd driver
python3 -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cd ..

# 6. Copy and edit configuration
cp config.toml.example config.toml
cp driver/config/driver.toml.example driver/config/driver.toml
cp driver/config/routes.toml.example driver/config/routes.toml
# Edit the three files — comments inside explain each setting

# 7. First-time Microsoft Graph authentication
cd driver
source .venv/bin/activate
python3 .claude/skills/todo-poll/poll.py --login
# Follow the device-code prompt in your browser
cd ..

# 8. Start the server
orchapi
```

---

## Verifying the install

```bash
# Check the binary version
orchapi --version
# or: ~/.local/share/orchapi/target/release/orchapi --version

# Check the health endpoint (server must be running)
curl -s http://127.0.0.1:7878/healthz | python3 -m json.tool
# Expected: {"status":"ok","version":"0.1.0"}

# Open the dashboard
open http://127.0.0.1:7878/ui         # macOS
xdg-open http://127.0.0.1:7878/ui     # Linux
start http://127.0.0.1:7878/ui        # Windows

# Verify poll.py can reach Graph (driver venv must be active)
cd /path/to/orchapi/driver
source .venv/bin/activate
python3 .claude/skills/todo-poll/poll.py
# Should print a JSON array (possibly empty if no pending tasks)
```

---

## Install flow diagram

```mermaid
flowchart TD
    START([curl install.sh | sh]):::usr
    CHK[Stage 1\nRust toolchain check\nauto-install if missing]:::srv
    PY[Stage 2\nPython 3 check\nfail if missing]:::srv
    VENV[Stage 3\nCreate driver/.venv\npip install -r requirements.txt]:::drv
    CLI[Stage 4\nCheck optional CLIs\nclaude / copilot / codex / pwsh]:::agt
    BUILD[Stage 5\ncargo build --release]:::srv
    CFG[Stage 6\nScaffold config files\nno-clobber copy from .example]:::sto
    LAUNCH[Stage 7\nWrite ~/.local/bin/orchapi\nlauncher script]:::srv
    DONE([Done — follow next steps]):::usr

    START --> CHK
    CHK --> PY
    PY --> VENV
    VENV --> CLI
    CLI --> BUILD
    BUILD --> CFG
    CFG --> LAUNCH
    LAUNCH --> DONE

    classDef srv fill:#6366f1,stroke:#4f46e5,color:#fff
    classDef drv fill:#10b981,stroke:#059669,color:#fff
    classDef gph fill:#0ea5e9,stroke:#0284c7,color:#fff
    classDef agt fill:#f59e0b,stroke:#d97706,color:#fff
    classDef sto fill:#64748b,stroke:#475569,color:#fff
    classDef usr fill:#f43f5e,stroke:#e11d48,color:#fff
```
