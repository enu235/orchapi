# Installing orchapi

## One-line install (recommended)

**macOS / Linux:**
```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh
```

**Windows (PowerShell 7+):**
```powershell
iwr -useb https://raw.githubusercontent.com/enu235/orchapi/main/install.ps1 | iex
```

The installer:
1. Checks prerequisites (Rust, Python, agent CLIs).
2. Clones the repo to `~/.local/share/orchapi` (macOS/Linux) or `%LOCALAPPDATA%\orchapi` (Windows).
3. Builds the `orchapi` binary with `cargo build --release`.
4. Adds the binary to your PATH.
5. Creates a Python virtual environment in `driver/.venv` and installs dependencies.

---

## Installer flags

| Flag | Description |
|---|---|
| `--prefix <dir>` | Install to a custom root directory instead of the default location |
| `--check-only` | Verify prerequisites and print what would be done; do not install |
| `--no-build` | Skip `cargo build --release` (useful if you have a pre-built binary) |
| `--upgrade` | Pull latest commits and rebuild in an existing installation |
| `--uninstall` | Remove the installation directory and PATH entry |

Example — install to `/opt/orchapi`:
```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --prefix /opt/orchapi
```

---

## Manual installation

### Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| Rust toolchain | 1.75 | Install via [rustup.rs](https://rustup.rs) |
| Python | 3.10 | Required for the driver |
| `claude` CLI | any | Claude Code — install from [claude.ai/code](https://claude.ai/code) |
| `copilot` CLI | any | Optional — GitHub Copilot CLI |
| `codex` CLI | any | Optional — OpenAI Codex CLI |

You only need the agent CLIs you intend to use.

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/enu235/orchapi.git
cd orchapi

# 2. Build the server binary
cargo build --release
# Binary is at target/release/orchapi

# 3. (Optional) put the binary on your PATH
cp target/release/orchapi ~/.local/bin/
# or add target/release/ to your PATH in ~/.bashrc / ~/.zshrc

# 4. Set up the Python driver
cd driver
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 5. Copy and edit configuration
cd ..
cp config.toml.example config.toml
cp driver/config/driver.toml.example driver/config/driver.toml
cp driver/config/routes.toml.example driver/config/routes.toml
# Edit the three files — see the comments inside each one

# 6. Start the server
orchapi
# or: ./target/release/orchapi
```

---

## First-time setup: authenticating with Microsoft Graph

The driver uses MSAL device-code flow to authenticate with Microsoft Graph. Run this once:

```bash
cd driver
source .venv/bin/activate
python3 .claude/skills/todo-poll/poll.py --login
```

A URL and a short code are printed. Open the URL in your browser, enter the code, and sign in with your Microsoft account (personal, work, or school). The token is written to `driver/state/token_cache.bin` and will be refreshed automatically.

**Required Microsoft Graph scopes:**
- `Tasks.ReadWrite` — read To-Do lists and mark tasks complete on writeback
- `Group.ReadWrite.All` — read and update Planner tasks

The default client ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`) is Microsoft's well-known public MSAL client and works for personal MSA accounts and most work/school tenants. If your organisation blocks it, register your own app in Entra ID and set `client_id` in `driver/config/driver.toml`.

---

## Upgrading

### Via the installer

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --upgrade
```

### Manually

```bash
cd /path/to/orchapi   # your clone
git pull
cargo build --release
cp target/release/orchapi ~/.local/bin/
# Restart the server
```

Driver dependencies:
```bash
cd driver
source .venv/bin/activate
pip install -r requirements.txt --upgrade
```

---

## Uninstalling

### Via the installer

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh -s -- --uninstall
```

### Manually

```bash
# Remove the binary
rm ~/.local/bin/orchapi

# Remove the repo (this also removes the driver venv and all session data)
rm -rf /path/to/orchapi
```

Token cache and session data live inside the repo directory, so removing the repo removes everything.

---

## Platform notes

### macOS

- Homebrew is not required. Xcode Command Line Tools (`xcode-select --install`) are needed by Cargo.
- `cargo` and `python3` are available via Homebrew (`brew install rust python`) or their respective official installers.
- The default `data_dir` is `./.orchapi` relative to the directory where you launch `orchapi`. Override in `config.toml` if needed.

### Linux

- Any distro with glibc 2.17+ should work.
- On Debian/Ubuntu: `sudo apt install build-essential pkg-config libssl-dev` before running `cargo build`.
- On Fedora/RHEL: `sudo dnf install gcc openssl-devel`.

### Windows

- PowerShell 7+ is required for the install script.
- The Rust toolchain requires Visual Studio Build Tools (MSVC) or the GNU toolchain. The `rustup` installer will guide you.
- Use forward slashes or double backslashes in `config.toml` paths, e.g. `cwd = "C:/Users/You/dev"`.
- The `cancel_grace_seconds` setting uses `CTRL_C_EVENT` on Windows instead of SIGTERM/SIGKILL.
- WSL2 is fully supported and behaves like Linux.
