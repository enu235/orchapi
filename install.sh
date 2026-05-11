#!/usr/bin/env bash
# install.sh — orchapi installer for macOS and Linux
#
# Usage:
#   curl-pipe:  curl --proto '=https' --tlsv1.2 -sSf \
#                 https://raw.githubusercontent.com/enu235/orchapi/main/install.sh | sh
#   from clone: ./install.sh [OPTIONS]
#
# Options:
#   --prefix DIR    Install root (default: ~/.local/share/orchapi when curl-piped,
#                   current directory when run from a clone)
#   --check-only    Print dependency status and exit
#   --no-build      Skip both release-binary download and cargo build
#   --build         Force cargo build --release even if a prebuilt release asset is available
#   --upgrade       git pull + rebuild from source (skip clone stage); implies --build
#   --uninstall     Remove launcher and venv, print manual cleanup note
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
stage()  { printf '\033[1;34m→\033[0m %s\n' "$1"; }
ok()     { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
fail()   { printf '\033[0;31m✗\033[0m %s\n' "$1"; exit 1; }
warn()   { printf '\033[0;33m!\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Argument parsing (must happen before any stage runs)
# ---------------------------------------------------------------------------
ARG_PREFIX=""
CHECK_ONLY=0
NO_BUILD=0
FORCE_BUILD=0
UPGRADE=0
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            ARG_PREFIX="$1"
            ;;
        --prefix=*)
            ARG_PREFIX="${1#--prefix=}"
            ;;
        --check-only)  CHECK_ONLY=1  ;;
        --no-build)    NO_BUILD=1    ;;
        --build)       FORCE_BUILD=1 ;;
        --upgrade)     UPGRADE=1     ;;
        --uninstall)   UNINSTALL=1   ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Detect curl|sh vs. direct execution
#
# When piped through bash, $0 is "bash" or "-bash" or "/bin/bash" — not a
# path into the repo.  A reliable signal is: does the directory containing
# $0 contain a Cargo.toml?
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
IS_PIPE_RUN=0
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/Cargo.toml" ]; then
    IS_PIPE_RUN=1
fi

# ---------------------------------------------------------------------------
# Resolve PREFIX (absolute path, determined once)
# ---------------------------------------------------------------------------
if [ -n "$ARG_PREFIX" ]; then
    PREFIX="$(cd "$ARG_PREFIX" 2>/dev/null && pwd || { mkdir -p "$ARG_PREFIX" && cd "$ARG_PREFIX" && pwd; })"
elif [ "$IS_PIPE_RUN" -eq 1 ]; then
    PREFIX="$HOME/.local/share/orchapi"
else
    PREFIX="$(pwd)"
fi

# ---------------------------------------------------------------------------
# Clone stage — only when curl-piped and not --upgrade
# ---------------------------------------------------------------------------
if [ "$IS_PIPE_RUN" -eq 1 ] && [ "$UPGRADE" -eq 0 ] && [ "$UNINSTALL" -eq 0 ] && [ "$CHECK_ONLY" -eq 0 ]; then
    if ! command -v git > /dev/null 2>&1; then
        fail "git is required to clone orchapi but was not found.
  macOS:        xcode-select --install
  Debian/Ubuntu: sudo apt install git
  Fedora/RHEL:   sudo dnf install git
After installing, re-run this installer."
    fi

    if [ ! -f "$PREFIX/Cargo.toml" ]; then
        stage "Cloning orchapi into $PREFIX"
        git clone https://github.com/enu235/orchapi.git "$PREFIX"
        ok "Cloned orchapi"
    else
        ok "Found existing clone at $PREFIX"
    fi
    # Re-exec the freshly cloned installer so all subsequent paths are correct
    exec bash "$PREFIX/install.sh" "$@" --prefix "$PREFIX"
fi

# From here on we are running from within (or re-exec'd into) a cloned repo.
# Ensure PREFIX is absolute.
PREFIX="$(cd "$PREFIX" && pwd)"

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    stage "Uninstalling orchapi"

    LAUNCHER="$HOME/.local/bin/orchapi"
    if [ -f "$LAUNCHER" ]; then
        rm -f "$LAUNCHER"
        ok "Removed launcher $LAUNCHER"
    else
        warn "Launcher $LAUNCHER not found (already removed?)"
    fi

    VENV="$PREFIX/driver/.venv"
    if [ -d "$VENV" ]; then
        rm -rf "$VENV"
        ok "Removed venv $VENV"
    else
        warn "Venv $VENV not found (already removed?)"
    fi

    printf '\n'
    printf 'Binary and database at %s can be removed manually with:\n' "$PREFIX"
    printf '  rm -rf %s\n' "$PREFIX"
    exit 0
fi

# ---------------------------------------------------------------------------
# --upgrade: pull latest before doing anything else
# ---------------------------------------------------------------------------
if [ "$UPGRADE" -eq 1 ]; then
    stage "Pulling latest changes"
    git -C "$PREFIX" pull --ff-only
    ok "Repository up to date"
fi

# ---------------------------------------------------------------------------
# Helper: compare version strings (returns 0 if $1 >= $2)
# Works with bash 3.2 (macOS default) — no regex in [[ ]].
# ---------------------------------------------------------------------------
version_ge() {
    # $1 = "1.85.0", $2 = "1.75.0"
    local a_major a_minor b_major b_minor
    a_major="$(printf '%s' "$1" | cut -d. -f1)"
    a_minor="$(printf '%s' "$1" | cut -d. -f2)"
    b_major="$(printf '%s' "$2" | cut -d. -f1)"
    b_minor="$(printf '%s' "$2" | cut -d. -f2)"
    if [ "$a_major" -gt "$b_major" ]; then return 0; fi
    if [ "$a_major" -eq "$b_major" ] && [ "$a_minor" -ge "$b_minor" ]; then return 0; fi
    return 1
}

# ---------------------------------------------------------------------------
# Detect OS / package manager (used for hints)
# ---------------------------------------------------------------------------
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    PYTHON_HINT="brew install python@3.12"
elif [ -f /etc/debian_version ]; then
    PYTHON_HINT="sudo apt install python3"
elif [ -f /etc/fedora-release ]; then
    PYTHON_HINT="sudo dnf install python3"
else
    PYTHON_HINT="Install Python 3.10+ from https://www.python.org/downloads/"
fi

# ---------------------------------------------------------------------------
# --check-only: gather status of all dependencies, print table, exit
# ---------------------------------------------------------------------------
if [ "$CHECK_ONLY" -eq 1 ]; then
    printf '\northapi dependency check\n\n'

    check_dep() {
        # $1 = binary, $2 = required version (or ""), $3 = optional label suffix
        local bin="$1"
        local req="$2"
        local label="${3:-}"
        local ver="" present=0

        if command -v "$bin" > /dev/null 2>&1; then
            present=1
            case "$bin" in
                rustc)   ver="$(rustc --version 2>/dev/null | awk '{print $2}')" ;;
                python3) ver="$(python3 --version 2>/dev/null | awk '{print $2}')" ;;
                claude)  ver="$(claude --version 2>/dev/null | head -1 | awk '{print $NF}')" ;;
                copilot) ver="$(copilot --version 2>/dev/null | head -1 | awk '{print $NF}')" ;;
                codex)   ver="$(codex --version 2>/dev/null | head -1 | awk '{print $NF}')" ;;
                pwsh)    ver="$(pwsh --version 2>/dev/null | awk '{print $2}')" ;;
                *)       ver="found" ;;
            esac
        fi

        if [ "$present" -eq 1 ]; then
            printf '  \033[0;32m✓\033[0m  %-12s %s%s\n' "$bin" "$ver" "${label:+  ($label)}"
        else
            local hint=""
            case "$bin" in
                rustc)   hint="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" ;;
                python3) hint="$PYTHON_HINT" ;;
                claude)  hint="npm install -g @anthropic-ai/claude-code" ;;
                copilot) hint="gh extension install github/gh-copilot" ;;
                codex)   hint="npm install -g @openai/codex" ;;
                pwsh)    hint="https://github.com/PowerShell/PowerShell/releases" ;;
            esac
            printf '  \033[0;31m✗\033[0m  %-12s not found  →  %s%s\n' "$bin" "$hint" "${label:+  ($label)}"
        fi
    }

    check_dep rustc   "1.75"
    check_dep python3 "3.10"
    check_dep claude  ""
    check_dep copilot ""
    check_dep codex   ""
    check_dep pwsh    "" "optional"

    printf '\n'
    exit 0
fi

# ---------------------------------------------------------------------------
# Build strategy
#   release-binary: download a prebuilt asset from the latest GitHub release
#   source:         cargo build --release from this clone (needs Rust)
#   none:           --no-build was passed
# ---------------------------------------------------------------------------
BUILD_STRATEGY="release-binary"
if [ "$UPGRADE"     -eq 1 ]; then BUILD_STRATEGY="source"; fi
if [ "$FORCE_BUILD" -eq 1 ]; then BUILD_STRATEGY="source"; fi
if [ "$NO_BUILD"    -eq 1 ]; then BUILD_STRATEGY="none";   fi

# ===========================================================================
# STAGE 1 — Rust toolchain (required only for source builds)
# ===========================================================================
stage "Rust toolchain"

RUST_OK=0
RUST_VER=""
if command -v rustc > /dev/null 2>&1; then
    RUST_VER="$(rustc --version | awk '{print $2}')"
    if version_ge "$RUST_VER" "1.75"; then
        RUST_OK=1
    fi
fi

if [ "$RUST_OK" -eq 1 ]; then
    ok "rustc $RUST_VER"
elif [ "$BUILD_STRATEGY" = "source" ]; then
    if [ -n "$RUST_VER" ]; then
        warn "rustc $RUST_VER is too old (need ≥ 1.75) — installing rustup"
    else
        warn "rustc not found — installing rustup"
    fi
    printf '\nInstalling rustup (this may take a minute)…\n'
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # Make cargo available in this session
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck source=/dev/null
        . "$HOME/.cargo/env"
    fi
    RUST_VER="$(rustc --version | awk '{print $2}')"
    RUST_OK=1
    ok "rustc $RUST_VER"
else
    warn "rustc not found (only needed for source builds; will use the prebuilt release binary)"
fi

# ===========================================================================
# STAGE 2 — Python
# ===========================================================================
stage "Python 3"

PYTHON_OK=0
PY_VER=""
if command -v python3 > /dev/null 2>&1; then
    PY_VER="$(python3 --version | awk '{print $2}')"
    if version_ge "$PY_VER" "3.10"; then
        PYTHON_OK=1
    fi
fi

if [ "$PYTHON_OK" -eq 0 ]; then
    if [ -n "$PY_VER" ]; then
        fail "python3 $PY_VER is too old (need ≥ 3.10). Install a newer Python: $PYTHON_HINT"
    else
        fail "python3 not found. Install it with: $PYTHON_HINT"
    fi
fi

ok "python3 $PY_VER"

# ===========================================================================
# STAGE 3 — Python venv
# ===========================================================================
stage "Python venv"

VENV_DIR="$PREFIX/driver/.venv"
VENV_ACTIVATE="$VENV_DIR/bin/activate"

if [ "$UPGRADE" -eq 1 ] || [ ! -f "$VENV_ACTIVATE" ]; then
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --quiet -r "$PREFIX/driver/requirements.txt"
    ok "Venv created and dependencies installed"
else
    ok "Venv already exists (skipping — use --upgrade to refresh)"
fi

# ===========================================================================
# STAGE 4 — Optional CLIs
# ===========================================================================
stage "Optional CLI tools"

check_optional() {
    local bin="$1"
    local hint="$2"
    local note="${3:-}"
    if ! command -v "$bin" > /dev/null 2>&1; then
        if [ -n "$note" ]; then
            warn "$bin not found (optional — $note).  Install: $hint"
        else
            warn "$bin not found.  Install: $hint"
        fi
    else
        local ver
        ver="$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}')" || ver="found"
        ok "$bin $ver"
    fi
}

check_optional "claude"  "npm install -g @anthropic-ai/claude-code  (or https://claude.ai/download)"
check_optional "copilot" "gh extension install github/gh-copilot  (note: orchapi expects standalone 'copilot' binary)"
check_optional "codex"   "npm install -g @openai/codex"
check_optional "pwsh"    "https://github.com/PowerShell/PowerShell/releases" \
    "only needed for PowerShell polling mode"

# ===========================================================================
# STAGE 5 — Obtain the orchapi binary
#
# release-binary: download from GitHub Releases (fast, no Rust needed)
# source:         cargo build --release (slow, requires Rust)
# ===========================================================================
BINARY_DEST="$PREFIX/target/release/orchapi"
BINARY_DEST_DIR="$(dirname "$BINARY_DEST")"

# Pick the asset name based on platform
ARCH="$(uname -m)"
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64|aarch64) ASSET_NAME="orchapi-macos-aarch64" ;;
            *)             ASSET_NAME="orchapi-macos-x86_64"  ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            aarch64|arm64) ASSET_NAME="orchapi-linux-aarch64" ;;
            *)             ASSET_NAME="orchapi-linux-x86_64"  ;;
        esac
        ;;
    *) ASSET_NAME="" ;;
esac

try_download_release_binary() {
    [ -z "$ASSET_NAME" ] && return 1
    local api="https://api.github.com/repos/enu235/orchapi/releases/latest"
    local rel
    if ! rel="$(curl -fsSL -H 'User-Agent: orchapi-installer' "$api" 2>/dev/null)"; then
        warn "Could not query GitHub releases (network/curl failure)"
        return 1
    fi
    # Extract browser_download_url for the matching asset
    local url
    url="$(printf '%s' "$rel" | awk -v name="$ASSET_NAME" '
        $0 ~ "\"name\": *\""name"\"" { found=1 }
        found && $0 ~ "browser_download_url" {
            sub(/.*"browser_download_url": *"/, "")
            sub(/".*/, "")
            print
            exit
        }')"
    if [ -z "$url" ]; then
        warn "Latest release has no asset named '$ASSET_NAME'"
        return 1
    fi
    mkdir -p "$BINARY_DEST_DIR"
    printf '    Downloading %s ...\n' "$ASSET_NAME"
    if ! curl -fsSL -H 'User-Agent: orchapi-installer' "$url" -o "$BINARY_DEST"; then
        warn "Download failed"
        return 1
    fi
    chmod +x "$BINARY_DEST"
    return 0
}

if [ "$BUILD_STRATEGY" = "none" ]; then
    stage "Skipping build (--no-build)"
    if [ ! -f "$BINARY_DEST" ]; then
        warn "No binary at $BINARY_DEST — \`orchapi\` will not run until you build or download one."
    fi
elif [ "$BUILD_STRATEGY" = "release-binary" ]; then
    stage "Fetching orchapi release binary"
    if try_download_release_binary; then
        ok "Installed prebuilt binary to $BINARY_DEST"
    elif [ "$RUST_OK" -eq 1 ]; then
        warn "Release binary unavailable; falling back to source build"
        BUILD_STRATEGY="source"
    else
        fail "Could not download a prebuilt release binary and Rust is not installed.
  - Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  - Or wait until a release asset for this platform is published."
    fi
fi

if [ "$BUILD_STRATEGY" = "source" ]; then
    stage "Building orchapi from source (cargo build --release)"
    BUILD_START="$(date +%s)"
    cargo build --release --manifest-path "$PREFIX/Cargo.toml"
    BUILD_END="$(date +%s)"
    BUILD_SECS=$((BUILD_END - BUILD_START))
    ok "Build complete in ${BUILD_SECS}s"
fi

# ===========================================================================
# STAGE 6 — Scaffold configs (no-clobber)
# ===========================================================================
stage "Scaffolding config files"

mkdir -p "$PREFIX/driver/state"

scaffold() {
    local src="$1"
    local dst="$2"
    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        ok "Created $dst"
    else
        ok "Already exists, skipping: $dst"
    fi
}

scaffold "$PREFIX/config.toml.example"                       "$PREFIX/config.toml"
scaffold "$PREFIX/driver/config/driver.toml.example"         "$PREFIX/driver/config/driver.toml"
scaffold "$PREFIX/driver/config/routes.toml.example"         "$PREFIX/driver/config/routes.toml"

# ===========================================================================
# STAGE 7 — Launcher
# ===========================================================================
stage "Writing launcher"

LAUNCHER_DIR="$HOME/.local/bin"
LAUNCHER="$LAUNCHER_DIR/orchapi"
mkdir -p "$LAUNCHER_DIR"

cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/usr/bin/env bash
# orchapi launcher — generated by install.sh
# The server reads profiles/ relative to its cwd, so we cd into the install
# root before exec-ing the binary.
cd "$PREFIX"
exec ./target/release/orchapi "\$@"
LAUNCHER_EOF

chmod +x "$LAUNCHER"
ok "Wrote $LAUNCHER"

# Warn if ~/.local/bin is not on PATH
case ":$PATH:" in
    *":$LAUNCHER_DIR:"*) ;;
    *)
        warn "$LAUNCHER_DIR is not on your PATH."
        warn "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

# ===========================================================================
# STAGE 8 — Next steps
# ===========================================================================
printf '\n'
printf '┌─────────────────────────────────────────────────────┐\n'
printf '│  orchapi installed!                                 │\n'
printf '│                                                     │\n'
printf '│  1. Authenticate with Microsoft Graph:              │\n'
printf '│     cd %s/driver\n' "$PREFIX"
printf '│     source .venv/bin/activate                       │\n'
printf '│     python3 .claude/skills/todo-poll/poll.py --login│\n'
printf '│                                                     │\n'
printf '│  2. Configure your routes:                          │\n'
printf '│     Edit driver/config/routes.toml                  │\n'
printf '│                                                     │\n'
printf '│  3. Start the server:                               │\n'
printf '│     orchapi                                         │\n'
printf '│     # or: cargo run (from %s)\n' "$PREFIX"
printf '│                                                     │\n'
printf '│  4. Open the dashboard:                             │\n'
printf '│     http://localhost:7878/ui                        │\n'
printf '│                                                     │\n'
printf '│  5. Run the driver (in Claude Code):                │\n'
printf '│     claude --cwd %s/driver\n' "$PREFIX"
printf '│     /loop 5m /poll-todos                            │\n'
printf '└─────────────────────────────────────────────────────┘\n'
printf '\n'
