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
    Skip both the release-binary download and `cargo build --release`. Useful when
    you want to refresh configs/venv without touching the binary.

.PARAMETER Build
    Force `cargo build --release` from source even when a prebuilt release binary
    is available. Requires the Rust toolchain.

.PARAMETER Upgrade
    Run `git pull` then rebuild from source. Skips clone stage. Implies -Build.

.PARAMETER Uninstall
    Remove the launcher and venv. Prints a manual cleanup note.
#>
[CmdletBinding()]
param(
    [string] $Prefix    = "",
    [switch] $CheckOnly,
    [switch] $NoBuild,
    [switch] $Build,
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
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail @"
git is required to clone orchapi but was not found.
  Windows: winget install --id Git.Git -e
  macOS:   xcode-select --install
  Linux:   sudo apt install git   (or your distro's equivalent)
After installing, restart your terminal and re-run this installer.
"@
    }

    if (-not (Test-Path (Join-Path $Prefix "Cargo.toml"))) {
        Write-Stage "Cloning orchapi into $Prefix"
        git clone https://github.com/enu235/orchapi.git $Prefix
        if ($LASTEXITCODE -ne 0) { Fail "git clone failed" }
        Write-Ok "Cloned orchapi"
    } else {
        Write-Ok "Found existing clone at $Prefix"
    }

    # Re-exec the freshly cloned installer.
    # NOTE: PowerShell parameters use a single dash (-Prefix), not POSIX double-dash.
    $clonedScript = Join-Path $Prefix "install.ps1"
    $extraArgs = @("-Prefix", $Prefix)
    if ($CheckOnly) { $extraArgs += "-CheckOnly" }
    if ($NoBuild)   { $extraArgs += "-NoBuild"   }
    if ($Build)     { $extraArgs += "-Build"     }
    if ($Upgrade)   { $extraArgs += "-Upgrade"   }
    if ($Uninstall) { $extraArgs += "-Uninstall" }
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
# Handles short forms like "1.75" by padding to "1.75.0", and rejects empty
# inputs (e.g. parsed from "Python was not found...") as 0.0.0.
# ---------------------------------------------------------------------------
function VersionGe {
    param([string]$a, [string]$b)
    function _Pad([string]$v) {
        $clean = ($v -replace '[^0-9.]','').Trim('.')
        $parts = @($clean.Split('.', [StringSplitOptions]::RemoveEmptyEntries))
        while ($parts.Count -lt 3) { $parts += '0' }
        return ($parts[0..2] -join '.')
    }
    return [Version]::new((_Pad $a)) -ge [Version]::new((_Pad $b))
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
# Build strategy
#
#   - release-binary: download orchapi.exe from the latest GitHub release
#                     (no Rust toolchain required)
#   - source        : `cargo build --release` from this clone (needs Rust)
#   - none          : -NoBuild was passed; skip both
#
# -Upgrade and -Build force source; -NoBuild forces none; otherwise we try
# release-binary first and fall back to source if the download fails AND
# Rust is available.
# ===========================================================================
$BuildStrategy = "release-binary"
if ($Upgrade) { $BuildStrategy = "source" }
if ($Build)   { $BuildStrategy = "source" }
if ($NoBuild) { $BuildStrategy = "none"   }

# ===========================================================================
# STAGE 1 — Rust toolchain (required only for source builds)
# ===========================================================================
Write-Stage "Rust toolchain"

$RustOk  = $false
$RustVer = ""
$rustCmd = Get-Command "rustc" -ErrorAction SilentlyContinue
if ($rustCmd) {
    $rustVerLine = rustc --version 2>&1 | Out-String
    $rustVerMatch = [regex]::Match($rustVerLine, '\d+\.\d+\.\d+')
    if ($rustVerMatch.Success) {
        $RustVer = $rustVerMatch.Value
        if (VersionGe $RustVer "1.75") { $RustOk = $true }
    }
}

if ($RustOk) {
    Write-Ok "rustc $RustVer"
} elseif ($BuildStrategy -eq "source") {
    if ($RustVer) {
        Write-Warn "rustc $RustVer is too old (need >= 1.75) — please install rustup"
    } else {
        Write-Warn "rustc not found — please install rustup"
    }
    Write-Host "  Run: winget install Rustlang.Rustup"
    Write-Host "  Then restart your terminal and re-run this installer."
    Fail "Rust toolchain required for source build"
} else {
    Write-Warn "rustc not found (only needed for source builds; will use the prebuilt release binary)"
}

# ===========================================================================
# STAGE 2 — Python
#
# On Windows, the Microsoft Store ships a "python3.exe" (and "python.exe")
# shim at %LOCALAPPDATA%\Microsoft\WindowsApps\ that prints
# "Python was not found; run without arguments to install from the Microsoft
# Store..." and exits non-zero. Get-Command returns it as a normal hit, so we
# have to probe each candidate and discard the shim before settling on one.
# ===========================================================================
Write-Stage "Python 3"

function Resolve-RealPython {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $exe = $cmd.Source
        # Skip the Microsoft Store App Execution Alias.
        if ($exe -like "*\WindowsApps\*") { continue }
        # Probe --version; the shim prints to stderr and exits non-zero.
        $out  = & $exe --version 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { continue }
        $line = ($out | Out-String).Trim()
        if ($line -match 'Python\s+(\d+\.\d+(?:\.\d+)?)') {
            return [PSCustomObject]@{ Exe = $exe; Version = $Matches[1] }
        }
    }
    return $null
}

$PyHit = Resolve-RealPython @('python3', 'python', 'py')

if (-not $PyHit) {
    Fail @"
Python 3.10+ not found (the Microsoft Store python3.exe/python.exe shim is not a real install).
  Install:   winget install Python.Python.3.12
  Or fetch:  https://www.python.org/downloads/
After installing, restart your terminal and re-run this installer.
"@
}

if (-not (VersionGe $PyHit.Version "3.10")) {
    Fail "Python $($PyHit.Version) at $($PyHit.Exe) is too old (need >= 3.10). Install: winget install Python.Python.3.12"
}

$Python3Exe = $PyHit.Exe
$PythonVer  = $PyHit.Version
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
# STAGE 5 — Obtain the orchapi binary
#
# release-binary path: download from GitHub Releases (fast, no Rust needed)
# source path:         cargo build --release (slow, requires Rust)
# ===========================================================================
$BinaryDest    = Join-Path $Prefix "target\release\orchapi.exe"
$BinaryDestDir = Split-Path $BinaryDest

function Try-DownloadReleaseBinary {
    param([string]$Destination)

    $apiUrl   = "https://api.github.com/repos/enu235/orchapi/releases/latest"
    $assetName = "orchapi-windows-x86_64.exe"

    try {
        $release = iwr -useb -Headers @{ "User-Agent" = "orchapi-installer" } $apiUrl
        $rel = $release.Content | ConvertFrom-Json
    } catch {
        Write-Warn "Could not query GitHub releases: $($_.Exception.Message)"
        return $false
    }

    $asset = $rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        Write-Warn "Release $($rel.tag_name) has no asset named '$assetName'"
        return $false
    }

    if (-not (Test-Path $BinaryDestDir)) {
        New-Item -ItemType Directory -Force -Path $BinaryDestDir | Out-Null
    }

    try {
        Write-Host ("    Downloading {0} ({1:N0} bytes) from release {2}..." -f $asset.name, $asset.size, $rel.tag_name)
        iwr -useb -Headers @{ "User-Agent" = "orchapi-installer" } $asset.browser_download_url -OutFile $Destination
    } catch {
        Write-Warn "Download failed: $($_.Exception.Message)"
        return $false
    }

    return $true
}

if ($BuildStrategy -eq "none") {
    Write-Stage "Skipping build (-NoBuild)"
    if (-not (Test-Path $BinaryDest)) {
        Write-Warn "No binary at $BinaryDest — `orchapi` will not run until you build or download one."
    }
}
elseif ($BuildStrategy -eq "release-binary") {
    Write-Stage "Fetching orchapi release binary"
    $downloaded = Try-DownloadReleaseBinary -Destination $BinaryDest
    if ($downloaded) {
        Write-Ok "Installed prebuilt binary to $BinaryDest"
    } else {
        if ($RustOk) {
            Write-Warn "Release binary unavailable; falling back to source build"
            $BuildStrategy = "source"
        } else {
            Fail @"
Could not download a prebuilt release binary and Rust is not installed.
  - Install Rust:  winget install Rustlang.Rustup  (then re-run this installer)
  - Or wait until a Windows release asset is published.
"@
        }
    }
}

if ($BuildStrategy -eq "source") {
    Write-Stage "Building orchapi from source (cargo build --release)"
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
