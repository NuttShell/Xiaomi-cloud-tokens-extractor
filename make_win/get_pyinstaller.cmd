<# : batch cmd 2>nul
@echo off
setlocal EnableDelayedExpansion
set "version=26.0827"
set "SCRIPTDIR=%~dp0"
set "SCRIPTDIR=%SCRIPTDIR:~0,-1%"
set "ARGS="!SCRIPTDIR!" %*"
if defined ARGS set "ARGS=%ARGS:"=\"%"
if defined ARGS set "ARGS=%ARGS:'=''%"
powershell -c ^"Invoke-Expression ('^& {' + (get-content -raw '%~f0') + '} %ARGS%')"
set "RC=%errorlevel%"
if not "%RC%"=="0" pause
exit /b %RC%
#>

param(
    [string]$ScriptDir,
    [switch]$Overwrite,
    [string]$Method = ""
)

if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }

function Write-Status {
    param([string]$Status, [string]$Detail = "")
    Write-Host "[*] $Status" -ForegroundColor Cyan
    if ($Detail -ne "") { Write-Host "    $Detail" -ForegroundColor Gray }
}

function Write-OK {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Red
}

function Get-PyInstallerVersion {
    param([string]$PythonExe)
    $out = & $PythonExe -m pip show pyinstaller 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in $out) {
        if ($line -match '^Version:\s*(.+)$') { return $Matches[1].Trim() }
    }
    return $null
}

# NOTE on Invoke-PipDirect: deliberately NOT Start-Process, and deliberately
# NOT a redirected-stream + Peek/ReadLine polling loop either. Both were tried
# for the from-source build previously and reproducibly hung partway through
# -- once even a Write-Host heartbeat with no dependency on the child process
# failed to appear, which points at something more fundamental than pipe
# buffering. A plain native call is the one thing that has run to completion
# every time, live pip/compiler output and all.
#
# The `| Out-Host` here is not optional cosmetics -- it fixes a real bug:
# `& $PythonExe @Arguments` is a pipeline call, so if this function's result
# is captured (e.g. `$exit = Invoke-PipDirect ...`), PowerShell bundles the
# child process's entire stdout into that same captured value alongside the
# later `return $LASTEXITCODE` -- not just the exit code. That silently broke
# every exit-code check in this script (a *successful* pip run could still
# read as non-zero, because the "value" being compared was stdout-text-plus-0,
# not the integer 0) and also meant no output appeared on screen until the
# process finished, since it was being captured instead of displayed.
# Piping through Out-Host displays each line immediately as it arrives and
# consumes it, so nothing leaks into the return value except $LASTEXITCODE.
function Invoke-PipDirect {
    param([string]$PythonExe, [string[]]$Arguments)
    & $PythonExe @Arguments | Out-Host
    return $LASTEXITCODE
}

function Install-ViaPip {
    param([string]$PythonExe, [string]$SdistPath = "")

    Write-Status "Removing any existing PyInstaller install and pip cache..."
    Invoke-PipDirect -PythonExe $PythonExe -Arguments @("-m", "pip", "uninstall", "pyinstaller", "-y") | Out-Null
    Invoke-PipDirect -PythonExe $PythonExe -Arguments @("-m", "pip", "cache", "remove", "pyinstaller") | Out-Null

    if ($SdistPath -and (Test-Path $SdistPath)) {
        Write-Status "Installing PyInstaller from the already-downloaded source archive..." $SdistPath
        $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
            "-m", "pip", "install", $SdistPath,
            "--no-warn-script-location", "--no-cache-dir"
        )
    } else {
        Write-Status "Installing PyInstaller via pip (prebuilt bootloader)..."
        $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
            "-m", "pip", "install", "pyinstaller",
            "--upgrade", "--no-warn-script-location", "--no-cache-dir"
        )
    }
    if ($exit -ne 0) {
        Write-Fail "pip install failed (exit $exit)"
        return $false
    }
    Write-OK "PyInstaller installed via pip"
    return $true
}

function Install-FromSource {
    param([string]$PythonExe, [string]$ScriptDir)

    # No upfront "is a compiler installed?" check here on purpose: cl.exe is
    # not on PATH even with a fully working MSVC Build Tools install unless
    # you're inside a Developer Command Prompt (post-vcvarsall). pip's own
    # build backend locates MSVC itself (vswhere/registry), independently of
    # PATH, so a Get-Command cl.exe check gives false negatives on machines
    # where the build would actually succeed. Simplest reliable signal is
    # just attempting the build and reacting to its real exit code below.
    $srcDir = Join-Path $ScriptDir "pyinstaller_src"
    if (Test-Path $srcDir) { Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item $srcDir -ItemType Directory -Force | Out-Null

    Write-Status "Downloading PyInstaller source distribution..."
    $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
        "-m", "pip", "download", "--no-binary", "pyinstaller",
        "--no-deps", "--no-cache-dir", "-d", $srcDir, "pyinstaller"
    )
    if ($exit -ne 0) {
        Write-Fail "pip download failed (exit $exit)"
        Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    $tarball = Get-ChildItem $srcDir -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
    if (-not $tarball) {
        Write-Fail "PyInstaller source archive not found after download"
        Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # No portable-MSVC environment loading here: confirmed that waf (which
    # PyInstaller's bootloader wscript delegates compiler detection to)
    # discovers MSVC via the Windows registry / VS Installer state, not via
    # PATH/INCLUDE/LIB -- so a manually-configured, unregistered portable
    # MSVC is invisible to it no matter when/how the env vars are set.
    # A real, registered Visual Studio / Build Tools install is the only
    # thing that works here (see the [O] option in the recovery menu below).

    Write-Status "Compiling bootloader from source and installing..." `
                 "This can take several minutes -- do not close this window"
    $env:PYINSTALLER_COMPILE_BOOTLOADER = "1"
    try {
        $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
            "-m", "pip", "install", $tarball.FullName,
            "--no-warn-script-location", "--no-cache-dir"
        )
    } finally {
        Remove-Item Env:\PYINSTALLER_COMPILE_BOOTLOADER -ErrorAction SilentlyContinue
    }

    if ($exit -ne 0) {
        Write-Fail "Source build/install failed (exit $exit)"
        # Deliberately NOT deleting $srcDir here: the recovery menu's [F]
        # option reuses this already-downloaded tarball instead of
        # re-fetching a wheel from PyPI.
        return $false
    }

    Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "PyInstaller installed from source (custom-compiled bootloader)"
    return $true
}

# ==================== MAIN ====================
$pythonDir = Join-Path $ScriptDir "python"
$py        = Join-Path $pythonDir "python.exe"

Write-Host ""
Write-Host "PyInstaller Installer (embedded Python)" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $py)) {
    Write-Fail "python.exe not found in: $pythonDir"
    Write-Host "  Run the embed-Python installer script first." -ForegroundColor Yellow
    exit 1
}

Write-Status "Checking Python installation..." $py
$verOut = (& $py --version 2>&1) -join ' '
if ($LASTEXITCODE -ne 0 -or $verOut -notmatch '^Python 3\.') {
    Write-Fail "python.exe did not report a valid Python 3.x version (got: '$verOut')"
    exit 1
}
Write-OK "Found: $verOut"

$existing = Get-PyInstallerVersion -PythonExe $py
if ($existing) {
    Write-Status "PyInstaller is already installed" "Version: $existing"
    if (-not $Overwrite) {
        while ($true) {
            $choice = (Read-Host "[R]einstall / [C]ancel").Trim().ToUpper()
            if ($choice -eq "C") { Write-Host "Cancelled." -ForegroundColor Yellow; exit 0 }
            if ($choice -eq "R") { break }
            Write-Host "  Invalid input, try again" -ForegroundColor Yellow
        }
    } else {
        Write-OK "Reinstalling (-Overwrite specified)"
    }
}

$selMethod = $Method.ToLower()
if ($selMethod -ne "" -and $selMethod -ne "pip" -and $selMethod -ne "source") {
    Write-Host "  Unrecognized -Method value '$Method' -- ignoring, will ask interactively" -ForegroundColor Yellow
    $selMethod = ""
}

if ($selMethod -eq "") {
    Write-Host ""
    Write-Host "Installation method:" -ForegroundColor Cyan
    Write-Host "  [P] pip install       -- fast, standard prebuilt bootloader" -ForegroundColor White
    Write-Host "  [S] build from source -- compiles bootloader, fewer AV false positives, slower" -ForegroundColor White
    Write-Host "  [C] cancel" -ForegroundColor White
    Write-Host ""
    while ($true) {
        $choice = (Read-Host "Select [P/S/C]").Trim().ToUpper()
        if ($choice -eq "C") { exit 0 }
        if ($choice -eq "P") { $selMethod = "pip"; break }
        if ($choice -eq "S") { $selMethod = "source"; break }
        Write-Host "  Invalid input, try again" -ForegroundColor Yellow
    }
} else {
    Write-OK "Using method from command line: $selMethod"
}

$ok = $false
if ($selMethod -eq "source") {
    $ok = Install-FromSource -PythonExe $py -ScriptDir $ScriptDir
    while (-not $ok) {
        Write-Host ""
        Write-Host "  [O] Official Build Tools for Visual Studio -- link + instructions, install yourself" -ForegroundColor White
        Write-Host "  [F] Fall back to the prebuilt pip wheel instead" -ForegroundColor White
        Write-Host "  [C] Cancel" -ForegroundColor White
        Write-Host ""
        $choice = (Read-Host "Select [O/F/C]").Trim().ToUpper()
        switch ($choice) {
            "O" {
                Write-Host ""
                Write-Host "  Build Tools for Visual Studio:" -ForegroundColor Cyan
                Write-Host "  https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor White
                Write-Host "  Run the installer, select the 'Desktop development with C++' workload," -ForegroundColor Gray
                Write-Host "  then re-run this script and choose [S] source build again." -ForegroundColor Gray
                try { Start-Process "https://visualstudio.microsoft.com/visual-cpp-build-tools/" } catch { }
                exit 1
            }
            "F" {
                $selMethod = "pip"
                $srcDir    = Join-Path $ScriptDir "pyinstaller_src"
                $sdist     = Get-ChildItem $srcDir -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue |
                             Select-Object -First 1
                $ok = Install-ViaPip -PythonExe $py -SdistPath $(if ($sdist) { $sdist.FullName } else { "" })
                Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            "C" { exit 1 }
            default { Write-Host "  Invalid input, try again" -ForegroundColor Yellow }
        }
        if ($choice -eq "F") { break }
    }
} else {
    $ok = Install-ViaPip -PythonExe $py
}

if (-not $ok) { exit 1 }

$finalVer = Get-PyInstallerVersion -PythonExe $py

Write-Host ""
Write-Host "==================== COMPLETE ====================" -ForegroundColor Green
Write-Host "Python      : $py"        -ForegroundColor White
Write-Host "PyInstaller : $finalVer"  -ForegroundColor White
Write-Host "Method      : $selMethod" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Read-Host -Prompt "Press any key to continue"