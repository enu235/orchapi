#Requires -Version 7
<#
.SYNOPSIS
    orchapi installer for Windows (PowerShell 7+)

.DESCRIPTION
    Installs the orchapi orchestration server and its Python driver.

    Supports curl-pipe install:
        iwr -useb https://raw.githubusercontent.com/enu235/orchapi/main/install.ps1 | iex

    And direct execution from a cloned repo:
        .\install.ps1 [options]

.PARAMETER Prefix
    Install root directory.
    Default when piped:      $env:LOCALAPPDATA\orchapi
    Default when from clone: current directory

.PARAMETER CheckOnly
    Print status of all dependencies and exit.

.PARAMETER NoBuild
    Skip `cargo build --release`.

.PARAMETER Upgrade
    Run `git pull` then rebuild. Skips clone stage.

.PARAMETER Uninstall
    Remove the launcher and venv. Prints a manual cleanup note.
#>
[CmdletBinding()]
param(
    [string] $Prefix    = "",
    [switch] $CheckOnly,
    [switch] $NoBuild,
    [switch] $Upgrade,
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
function Write-Stage { param([string]$msg) Write-Host "-> $msg" -ForegroundColor Blue   }
function Write-Ok    { param([string]$msg) Write-Host "v  $msg" -ForegroundColor Green  }
function Write-Fail  { param([string]$msg) Write-Host "x  $msg" -ForegroundColor Red    }
function Write-Warn  { param([string]$msg) Write-Host "!  $msg" -ForegroundColor Yellow }

function Fail {
    param([string]$msg)
    Write-Fail $msg
    exit 1
}

# ---------------------------------------------------------------------------
# Detect piped-in vs. direct execution
#
# When piped via `iex`, $PSCommandPath is empty and $MyInvocation.MyCommand
# is a ScriptBlock, not a path.  We treat "no Cargo.toml next to the script"
# as the reliable signal.
# ---------------------------------------------------------------------------
$ScriptDir = ""
try {
    if ($PSCommandPath) {
        $ScriptDir = Split-Path -Parent $PSCommandPath
    }
} catch {}

$IsPipeRun = $true
if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "Cargo.toml"))) {
    $IsPipeRun = $false
}

# ---------------------------------------------------------------------------
# Resolve PREFIX (absolute path)
# ---------------------------------------------------------------------------
if ($Prefix -ne "") {
    if (-not (Test-Path $Prefix)) {
        New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    }
    $Prefix = (Resolve-Path $Prefix).Path
} elseif ($IsPipeRun) {
    $Prefix = Join-Path $env:LOCALAPPDATA "orchapi"
} else {
    $Prefix = (Get-Location).Path
}

# ---------------------------------------------------------------------------
# Clone stage — only when piped and not --upgrade / --uninstall / --check
# ---------------------------------------------------------------------------
if ($IsPipeRun -and -not $Upgrade -and -not $Uninstall -and -not $CheckOnly) {
    if (-not (Test-Path (Join-Path $Prefix "Cargo.toml"))) {
        Write-Stage "Cloning orchapi into $Prefix"
        git clone https://github.com/enu235/orchapi.git $Prefix
        if ($LASTEXITCODE -ne 0) { Fail "git clone failed" }
        Write-Ok "Cloned orchapi"
    } else {
        Write-Ok "Found existing clone at $Prefix"
    }

    # Re-exec the freshly cloned installer
    $clonedScript = Join-Path $Prefix "install.ps1"
    $extraArgs = @("--Prefix", $Prefix)
    if ($CheckOnly) { $extraArgs += "--CheckOnly" }
    if ($NoBuild)   { $extraArgs += "--NoBuild"   }
    if ($Upgrade)   { $extraArgs += "--Upgrade"   }
    if ($Uninstall) { $extraArgs += "--Uninstall" }
    & $clonedScript @extraArgs
    exit $LASTEXITCODE
}

# Ensure absolute path from here on
if (-not (Test-Path $Prefix)) {
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
}
$Prefix = (Resolve-Path $Prefix).Path

# ---------------------------------------------------------------------------
# Helper: compare version strings (returns $true if $a >= $b)
# ---------------------------------------------------------------------------
function VersionGe {
    param([string]$a, [string]$b)
    $av = [Version]::new(($a -replace '[^0-9.]','').TrimEnd('.').Split('.')[0..2] -join '.')
    $bv = [Version]::new(($b -replace '[^0-9.]','').TrimEnd('.').Split('.')[0..2] -join '.')
    return $av -ge $bv
}

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------
if ($Uninstall) {
    Write-Stage "Uninstalling orchapi"

    $LauncherDir = Join-Path $env:USERPROFILE ".local\bin"
    $LauncherCmd = Join-Path $LauncherDir "orchapi.cmd"

    if (Test-Path $LauncherCmd) {
        Remove-Item $LauncherCmd -Force
        Write-Ok "Removed launcher $LauncherCmd"
    } else {
        Write-Warn "Launcher $LauncherCmd not found (already removed?)"
    }

    $VenvDir = Join-Path $Prefix "driver\.venv"
    if (Test-Path $VenvDir) {
        Remove-Item $VenvDir -Recurse -Force
        Write-Ok "Removed venv $VenvDir"
    } else {
        Write-Warn "Venv $VenvDir not found (already removed?)"
    }

    Write-Host ""
    Write-Host "Binary and database at $Prefix can be removed manually with:"
    Write-Host "  Remove-Item -Recurse -Force `"$Prefix`""
    exit 0
}

# ---------------------------------------------------------------------------
# --upgrade: pull latest before doing anything else
# ---------------------------------------------------------------------------
if ($Upgrade) {
    Write-Stage "Pulling latest changes"
    git -C $Prefix pull --ff-only
    if ($LASTEXITCODE -ne 0) { Fail "git pull failed" }
    Write-Ok "Repository up to date"
}

# ---------------------------------------------------------------------------
# --check-only: dependency table, then exit
# ---------------------------------------------------------------------------
if ($CheckOnly) {
    Write-Host ""
    Write-Host "orchapi dependency check"
    Write-Host ""

    function Check-Dep {
        param(
            [string]$Bin,
            [string]$Required = "",
            [string]$Note = ""
        )
        $cmd = Get-Command $Bin -ErrorAction SilentlyContinue
        if ($cmd) {
            $ver = ""
            try {
                $verOut = & $Bin --version 2>&1 | Select-Object -First 1
                $ver = ($verOut -split '\s+' | Where-Object { $_ -match '^[\d]' } | Select-Object -First 1)
                if (-not $ver) { $ver = ($verOut -split '\s+' | Select-Object -Last 1) }
            } catch { $ver = "found" }
            $suffix = if ($Note) { "  ($Note)" } else { "" }
            Write-Host ("  " + [char]0x2713 + "  {0,-12} {1}{2}" -f $Bin, $ver, $suffix) -ForegroundColor Green
        } else {
            $hint = switch ($Bin) {
                "rustc"   { "winget install Rustlang.Rustup" }
                "python3" { "winget install Python.Python.3.12" }
                "claude"  { "npm install -g @anthropic-ai/claude-code" }
                "copilot" { "gh extension install github/gh-copilot" }
                "codex"   { "npm install -g @openai/codex" }
                "pwsh"    { "winget install Microsoft.PowerShell" }
                default   { "see docs" }
            }
            $suffix = if ($Note) { "  ($Note)" } else { "" }
            Write-Host ("  " + [char]0x2717 + "  {0,-12} not found  ->  {1}{2}" -f $Bin, $hint, $suffix) -ForegroundColor Red
        }
    }

    Check-Dep "rustc"   "1.75"
    Check-Dep "python3" "3.10"
    Check-Dep "claude"
    Check-Dep "copilot"
    Check-Dep "codex"
    Check-Dep "pwsh" "" "optional"

    Write-Host ""
    exit 0
}

# ===========================================================================
# STAGE 1 — Rust toolchain
# ===========================================================================
Write-Stage "Rust toolchain"

$RustOk  = $false
$RustVer = ""
$rustCmd = Get-Command "rustc" -ErrorAction SilentlyContinue
if ($rustCmd) {
    $RustVer = (rustc --version | Select-String -Pattern '\d+\.\d+\.\d+').Matches[0].Value
    if (VersionGe $RustVer "1.75") {
        $RustOk = $true
    }
}

if (-not $RustOk) {
    if ($RustVer) {
        Write-Warn "rustc $RustVer is too old (need >= 1.75) — please install rustup"
    } else {
        Write-Warn "rustc not found — please install rustup"
    }
    Write-Host "  Run: winget install Rustlang.Rustup"
    Write-Host "  Then restart your terminal and re-run this installer."
    Fail "Rust toolchain required"
}

Write-Ok "rustc $RustVer"

# ===========================================================================
# STAGE 2 — Python
# ===========================================================================
Write-Stage "Python 3"

$PythonOk  = $false
$PythonVer = ""
$pyCmd = Get-Command "python3" -ErrorAction SilentlyContinue
if (-not $pyCmd) {
    # On Windows, 'python' (not 'python3') is common
    $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
}
if ($pyCmd) {
    $pyVerRaw = & $pyCmd.Source --version 2>&1
    $PythonVer = ($pyVerRaw -split '\s+')[1]
    if (VersionGe $PythonVer "3.10") {
        $PythonOk = $true
    }
}

if (-not $PythonOk) {
    if ($PythonVer) {
        Fail "Python $PythonVer is too old (need >= 3.10). Install: winget install Python.Python.3.12"
    } else {
        Fail "Python 3 not found. Install: winget install Python.Python.3.12"
    }
}

# Normalise: ensure 'python3' resolves for subsequent calls
$Python3Exe = $pyCmd.Source
Write-Ok "python3 $PythonVer ($Python3Exe)"

# ===========================================================================
# STAGE 3 — Python venv
# ===========================================================================
Write-Stage "Python venv"

$VenvDir      = Join-Path $Prefix "driver\.venv"
$VenvActivate = Join-Path $VenvDir "Scripts\Activate.ps1"
$VenvPip      = Join-Path $VenvDir "Scripts\pip.exe"

if ($Upgrade -or -not (Test-Path $VenvActivate)) {
    & $Python3Exe -m venv $VenvDir
    & $VenvPip install --quiet -r (Join-Path $Prefix "driver\requirements.txt")
    Write-Ok "Venv created and dependencies installed"
} else {
    Write-Ok "Venv already exists (skipping -- use -Upgrade to refresh)"
}

# ===========================================================================
# STAGE 4 — Optional CLIs
# ===========================================================================
Write-Stage "Optional CLI tools"

function Check-Optional {
    param(
        [string]$Bin,
        [string]$Hint,
        [string]$Note = ""
    )
    $cmd = Get-Command $Bin -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $suffix = if ($Note) { " (optional -- $Note)" } else { "" }
        Write-Warn "$Bin not found$suffix.  Install: $Hint"
    } else {
        $ver = ""
        try {
            $verOut = & $Bin --version 2>&1 | Select-Object -First 1
            $ver = ($verOut -split '\s+' | Where-Object { $_ -match '^\d' } | Select-Object -First 1)
            if (-not $ver) { $ver = ($verOut -split '\s+' | Select-Object -Last 1) }
        } catch { $ver = "found" }
        Write-Ok "$Bin $ver"
    }
}

Check-Optional "claude"  "npm install -g @anthropic-ai/claude-code  (or https://claude.ai/download)"
Check-Optional "copilot" "gh extension install github/gh-copilot  (note: orchapi expects standalone 'copilot' binary)"
Check-Optional "codex"   "npm install -g @openai/codex"
Check-Optional "pwsh"    "winget install Microsoft.PowerShell" "only needed for PowerShell polling mode"

# ===========================================================================
# STAGE 5 — Build
# ===========================================================================
Write-Stage "Building orchapi (release)"

if ($NoBuild) {
    Write-Warn "Skipping build (-NoBuild)"
} else {
    $BuildStart = Get-Date
    $manifestPath = Join-Path $Prefix "Cargo.toml"
    cargo build --release --manifest-path $manifestPath
    if ($LASTEXITCODE -ne 0) { Fail "cargo build failed" }
    $BuildSecs = [int]((Get-Date) - $BuildStart).TotalSeconds
    Write-Ok "Build complete in ${BuildSecs}s"
}

# ===========================================================================
# STAGE 6 — Scaffold configs (no-clobber)
# ===========================================================================
Write-Stage "Scaffolding config files"

$StateDir = Join-Path $Prefix "driver\state"
if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
}

function Scaffold {
    param([string]$Src, [string]$Dst)
    if (-not (Test-Path $Dst)) {
        Copy-Item $Src $Dst
        Write-Ok "Created $Dst"
    } else {
        Write-Ok "Already exists, skipping: $Dst"
    }
}

$ConfigTomlDst    = Join-Path $Prefix "config.toml"
$DriverTomlDst    = Join-Path $Prefix "driver\config\driver.toml"
$RoutesTomlDst    = Join-Path $Prefix "driver\config\routes.toml"

$ConfigTomlSrc    = Join-Path $Prefix "config.toml.example"
$DriverTomlSrc    = Join-Path $Prefix "driver\config\driver.toml.example"
$RoutesTomlSrc    = Join-Path $Prefix "driver\config\routes.toml.example"

# config.toml: scaffold then fix Windows-inappropriate cwd path
if (-not (Test-Path $ConfigTomlDst)) {
    Copy-Item $ConfigTomlSrc $ConfigTomlDst
    # Replace the Unix /tmp default with a Windows-appropriate temp path
    $content = Get-Content $ConfigTomlDst -Raw
    $content = $content -replace 'cwd\s*=\s*"/tmp"', 'cwd = "$env:TEMP"'
    Set-Content $ConfigTomlDst $content -NoNewline
    Write-Ok "Created $ConfigTomlDst (patched cwd for Windows)"
} else {
    Write-Ok "Already exists, skipping: $ConfigTomlDst"
}

Scaffold $DriverTomlSrc $DriverTomlDst
Scaffold $RoutesTomlSrc $RoutesTomlDst

# ===========================================================================
# STAGE 7 — Launcher (.cmd wrapper)
# ===========================================================================
Write-Stage "Writing launcher"

$LauncherDir = Join-Path $env:USERPROFILE ".local\bin"
$LauncherCmd = Join-Path $LauncherDir "orchapi.cmd"

if (-not (Test-Path $LauncherDir)) {
    New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null
}

$BinaryPath = Join-Path $Prefix "target\release\orchapi.exe"

$launcherContent = @"
@echo off
rem orchapi launcher -- generated by install.ps1
rem The server reads profiles\ relative to its cwd, so we cd into the
rem install root before executing the binary.
cd /d "$Prefix"
.\target\release\orchapi.exe %*
"@

Set-Content -Path $LauncherCmd -Value $launcherContent -Encoding ASCII
Write-Ok "Wrote $LauncherCmd"

# Add ~/.local/bin to user PATH if not already present
$UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if (-not ($UserPath -split ";" | Where-Object { $_ -eq $LauncherDir })) {
    $NewUserPath = if ($UserPath) { "$UserPath;$LauncherDir" } else { $LauncherDir }
    [System.Environment]::SetEnvironmentVariable("PATH", $NewUserPath, "User")
    Write-Ok "Added $LauncherDir to user PATH (restart your terminal to pick it up)"
} else {
    Write-Ok "$LauncherDir is already on PATH"
}

# ===========================================================================
# STAGE 8 — Next steps
# ===========================================================================
Write-Host ""
Write-Host "+---------------------------------------------------------+"
Write-Host "|  orchapi installed!                                     |"
Write-Host "|                                                         |"
Write-Host "|  1. Authenticate with Microsoft Graph:                  |"
Write-Host "|     cd $Prefix\driver"
Write-Host "|     & .\.venv\Scripts\Activate.ps1                      |"
Write-Host "|     python3 .claude/skills/todo-poll/poll.py --login    |"
Write-Host "|                                                         |"
Write-Host "|  2. Configure your routes:                              |"
Write-Host "|     Edit driver\config\routes.toml                      |"
Write-Host "|                                                         |"
Write-Host "|  3. Start the server:                                   |"
Write-Host "|     orchapi                                             |"
Write-Host "|     # or: cargo run (from $Prefix)"
Write-Host "|                                                         |"
Write-Host "|  4. Open the dashboard:                                 |"
Write-Host "|     http://localhost:7878/ui                            |"
Write-Host "|                                                         |"
Write-Host "|  5. Run the driver (in Claude Code):                    |"
Write-Host "|     claude --cwd $Prefix\driver"
Write-Host "|     /loop 5m /poll-todos                                |"
Write-Host "+---------------------------------------------------------+"
Write-Host ""
