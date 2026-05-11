# Installing orchapi

## One-line install (recommended)

**macOS / Linux:**
```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/master/install.sh | sh
```

**Windows (PowerShell 7+):**
```powershell
iwr -useb https://raw.githubusercontent.com/enu235/orchapi/master/install.ps1 | iex
```

> **Windows prerequisites:** PowerShell 7+ (`winget install Microsoft.PowerShell`),
> Git (`winget install --id Git.Git -e`), and Rust (`winget install Rustlang.Rustup`)
> must be installed first. If `iwr | iex` is blocked by execution policy, run
> instead: `pwsh -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/enu235/orchapi/master/install.ps1 | iex"`.

The installer:
1. Checks prerequisites (Python, Git; Rust only if it has to build from source).
2. Clones the repo to `~/.local/share/orchapi` (macOS/Linux) or `%LOCALAPPDATA%\orchapi` (Windows).
3. Downloads the prebuilt `orchapi` binary from the [latest GitHub release](https://github.com/enu235/orchapi/releases/latest) for your platform. If no asset exists for your OS/arch, it falls back to `cargo build --release` from source.
4. Adds the binary to your PATH.
5. Creates a Python virtual environment in `driver/.venv` and installs dependencies.

---

## Installer flags

| Flag | Description |
|---|---|
| `--prefix <dir>` | Install to a custom root directory instead of the default location |
| `--check-only` | Verify prerequisites and print what would be done; do not install |
| `--no-build` | Skip both the release-binary download and `cargo build` (useful if you've placed a binary at `target/release/orchapi` yourself) |
| `--build` | Force a `cargo build --release` from source even when a prebuilt release asset is available. Requires the Rust toolchain. |
| `--upgrade` | Pull latest commits and rebuild from source in an existing installation. Implies `--build`. |
| `--uninstall` | Remove the installation directory and PATH entry |

On Windows, the same flags use single-dash PowerShell syntax: `-Prefix`, `-CheckOnly`, `-NoBuild`, `-Build`, `-Upgrade`, `-Uninstall`.

Example — install to `/opt/orchapi`:
```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/enu235/orchapi/master/install.sh | sh -s -- --prefix /opt/orchapi
```

---

## Manual installation

### Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| Rust toolchain | 1.75 | Install via [rustup.rs](https://rustup.rs). On Windows use `winget install Rustlang.Rustup`. |
| Python | 3.10 | Required for the driver. **Windows:** the Microsoft Store `python3.exe` shim is *not* a real install — install from [python.org](https://www.python.org/downloads/) or `winget install Python.Python.3.12`. |
| Git | 2.x | Needed by the installer and by `--upgrade`. **Windows:** `winget install --id Git.Git -e`. |
| PowerShell | 7+ | Windows only. The installer uses PowerShell-7 features. `winget install Microsoft.PowerShell`. |
| `claude` CLI | any | Required to drive orchapi via Claude Code, or dispatch Claude child sessions. Install from [claude.ai/code](https://claude.ai/code) |
| `copilot` CLI | any | Required to drive orchapi via Copilot CLI, or dispatch Copilot child sessions. See [docs/executors/copilot.md](docs/executors/copilot.md) |
| `codex` CLI | any | Required to dispatch Codex child sessions. See [docs/executors/codex.md](docs/executors/codex.md) |

Install only the CLIs you intend to use. The orchapi server and driver Python skills work regardless of which CLIs are present.

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
  https://raw.githubusercontent.com/enu235/orchapi/master/install.sh | sh -s -- --upgrade
```

On Windows:
```powershell
iwr -useb https://raw.githubusercontent.com/enu235/orchapi/master/install.ps1 | iex
# then re-run with -Upgrade from the install root:
& "$env:LOCALAPPDATA\orchapi\install.ps1" -Upgrade
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
  https://raw.githubusercontent.com/enu235/orchapi/master/install.sh | sh -s -- --uninstall
```

On Windows, run `install.ps1 -Uninstall` from the install root:
```powershell
& "$env:LOCALAPPDATA\orchapi\install.ps1" -Uninstall
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

- PowerShell 7+ is required for the install script. Install with `winget install Microsoft.PowerShell` and re-launch as `pwsh`.
- Git is required for clone/upgrade. Install with `winget install --id Git.Git -e`.
- The Rust toolchain requires Visual Studio Build Tools (MSVC) or the GNU toolchain. Install via `winget install Rustlang.Rustup`; the `rustup` installer will guide you through MSVC.
- **Microsoft Store Python shim:** by default `python3.exe` (and `python.exe`) under `%LOCALAPPDATA%\Microsoft\WindowsApps\` are not Python — they're forwarders that prompt you to install from the Store. Install a real Python from [python.org](https://www.python.org/downloads/) or via `winget install Python.Python.3.12`, then restart your terminal. The installer detects the shim and skips past it to a real Python binary on PATH.
- **Execution policy:** the default `RemoteSigned` policy blocks `iwr | iex` for downloaded scripts. Either set `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` (or `Bypass`), or run the one-liner via `pwsh -ExecutionPolicy Bypass -Command "iwr -useb …  | iex"`.
- Use forward slashes or double backslashes in `config.toml` paths, e.g. `cwd = "C:/Users/You/dev"`.
- The `cancel_grace_seconds` setting uses `CTRL_C_EVENT` on Windows instead of SIGTERM/SIGKILL.
- WSL2 is fully supported and behaves like Linux.
