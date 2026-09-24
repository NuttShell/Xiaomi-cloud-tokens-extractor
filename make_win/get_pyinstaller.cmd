<# : batch cmd 2>nul
@echo off
setlocal EnableDelayedExpansion
set "version=26.0921"

set "NOWAIT="
for %%A in (%*) do (
    if /I "%%~A"=="-nowait" set "NOWAIT=1"
)

set ARGS= %*
if defined ARGS set "ARGS=%ARGS:\"="%"
if defined ARGS set "ARGS=%ARGS:\"="%"
if defined ARGS set "ARGS=%ARGS:"=\"%"
if defined ARGS set "ARGS=%ARGS:'=''%"

powershell -NoProfile -ExecutionPolicy Bypass -c ^"$version='%version%'; Invoke-Expression ('^& {' + (get-content -raw '%~f0') + '} %ARGS%')"
set "RC=%errorlevel%"
if not "%RC%"=="0" if not defined NOWAIT pause
exit /b %RC%
#>

param(
    [switch]$Overwrite,
    [string]$Method = "",
    [switch]$RequireCompiler,
    [switch]$CheckTools,
    [switch]$DeepCheck,
    [switch]$NoWait,
    [Alias("h")]
    [switch]$Help
)

if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).ProviderPath }

$BUILDTOOLS_URL = "https://visualstudio.microsoft.com/visual-cpp-build-tools/"

function Write-Status {
    param([string]$Status, [string]$Detail = "")
    Write-Host "[*] $Status" -ForegroundColor Cyan
    if ($Detail -ne "") { Write-Host "    $Detail" -ForegroundColor Gray }
}

function Write-OK {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[~] $Message" -ForegroundColor Yellow
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

function Get-PythonBitness {
    param([string]$PythonExe)
    $out = (& $PythonExe -c "import struct;print(struct.calcsize('P')*8)" 2>$null | Select-Object -First 1)
    if ($out -match '^\s*(32|64)\s*$') { return [int]$Matches[1] }
    return 64
}

# ==================== MSVC DETECTION ====================
#
# This mirrors what waf (waflib/Tools/msvc.py) does, because waf is what
# PyInstaller's bootloader wscript delegates compiler detection to. Doing it
# any other way produces answers that disagree with the thing that actually
# runs the build:
#
#   gather_vswhere_versions() -> runs
#       %ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
#       -products * -legacy -format json
#     and takes installationPath / installationVersion from the JSON.
#   gather_msvc_versions()    -> registry, HKLM\SOFTWARE\[Wow6432node\]Microsoft\
#       VisualStudio|VCExpress\<ver>\Setup\VC\ProductDir, falling back to
#       ...\VisualStudio\SxS\VS7. (This registry-only discovery is exactly why a
#       manually unpacked "portable" MSVC stays invisible -- see the note in
#       Install-FromSource.)
#   gather_msvc_targets()     -> locates the environment batch file inside an
#       install, in this order: VC\Auxiliary\Build\vcvarsall.bat, vcvarsall.bat,
#       Common7\Tools\vsvars32.bat, Bin\vcvars32.bat.
#   get_msvc_version()        -> the real verification step: writes a temp .bat
#       that calls vcvarsall for the target arch, checks INCLUDE/LIB got set,
#       and runs the compiler once to prove it starts.
#
# Note what is deliberately NOT used here: PATH, Get-Command cl.exe, or
# %VCINSTALLDIR%. cl.exe is not on PATH outside a Developer Command Prompt even
# on a perfectly working install, so a PATH-based probe gives false negatives on
# machines where the build would succeed.

function Find-VsWhere {
    $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles, "C:\Program Files (x86)")
    foreach ($r in $roots) {
        if (-not $r) { continue }
        $p = Join-Path $r "Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-VcVarsAll {
    param([string]$InstallPath)
    # Same candidate order as waf's gather_msvc_targets().
    $candidates = @(
        "VC\Auxiliary\Build\vcvarsall.bat",
        "vcvarsall.bat",
        "VC\vcvarsall.bat",
        "Common7\Tools\vsvars32.bat",
        "Bin\vcvars32.bat"
    )
    foreach ($c in $candidates) {
        $full = Join-Path $InstallPath $c
        if (Test-Path $full) { return $full }
    }
    return $null
}

function Get-MsvcInstalls {
    # Fast pass only: locate installs and their vcvarsall batch file. No
    # process is launched here beyond vswhere itself, so this is cheap enough
    # to run before the method menu.
    $found = @()

    $vswhere = Find-VsWhere
    if ($vswhere) {
        try {
            $raw = (& $vswhere -products '*' -legacy -format json 2>$null) -join "`n"
            if ($raw.Trim() -ne "") {
                $entries = $raw | ConvertFrom-Json
                foreach ($e in @($entries)) {
                    if (-not $e.installationPath) { continue }
                    if (-not (Test-Path $e.installationPath)) { continue }
                    $bat = Find-VcVarsAll -InstallPath $e.installationPath
                    if (-not $bat) { continue }
                    $found += [PSCustomObject]@{
                        Name      = $(if ($e.displayName) { $e.displayName } else { "Visual Studio" })
                        Version   = [string]$e.installationVersion
                        Path      = [string]$e.installationPath
                        VcVarsAll = $bat
                        Source    = "vswhere"
                    }
                }
            }
        } catch {
            # vswhere missing, too old, or emitting non-UTF8 JSON -- fall through
            # to the registry pass rather than failing detection outright.
        }
    }

    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VS7",
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\SxS\VS7",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VC7",
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\SxS\VC7"
    )) {
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -notmatch '^\d+\.\d+$') { continue }
            $path = [string]$p.Value
            if (-not $path -or -not (Test-Path $path)) { continue }
            $path = $path.TrimEnd('\')
            if ($found | Where-Object { $_.Path -eq $path }) { continue }
            $bat = Find-VcVarsAll -InstallPath $path
            if (-not $bat) { continue }
            $found += [PSCustomObject]@{
                Name      = "Visual C++ $($p.Name) (registry)"
                Version   = $p.Name
                Path      = $path
                VcVarsAll = $bat
                Source    = "registry"
            }
        }
    }

    return @($found | Sort-Object -Property @{
        Expression = {
            $v = 0.0
            [double]::TryParse(($_.Version -replace '^(\d+\.\d+).*$', '$1'),
                               [ref]$v) | Out-Null
            $v
        }
        Descending = $true
    })
}

function Get-OsArch {
    # PROCESSOR_ARCHITEW6432 is set only when a 32-bit process runs on a 64-bit
    # OS, so it wins when present -- otherwise a 32-bit PowerShell would report
    # the machine as x86.
    $a = $env:PROCESSOR_ARCHITEW6432
    if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    switch ("$a".ToUpper()) {
        "AMD64" { return "x64" }
        "ARM64" { return "arm64" }
        "X86"   { return "x86" }
        default { return "x64" }
    }
}

function Get-VcVarsTarget {
    param([string]$HostArch, [string]$TargetArch, [bool]$Legacy)
    # The argument vcvarsall.bat expects for this host/target pair. Native pairs
    # are a single word, cross pairs are host_target.
    if ($Legacy) {
        if ($HostArch -eq $TargetArch) {
            if ($TargetArch -eq "x64") { return "amd64" }
            return "x86"
        }
        if ($TargetArch -eq "x64") { return "x86_amd64" }
        return "amd64_x86"
    }
    if ($HostArch -eq $TargetArch) { return $TargetArch }
    return ($HostArch + "_" + $TargetArch)
}

function Get-DefaultToolsetVersion {
    param([string]$InstallPath)
    # vcvarsall.bat picks the toolset from this file unless -vcvars_ver= is
    # passed, so it -- not "newest directory on disk" -- is what the build will
    # actually use. With several toolsets side by side in one install the two
    # can disagree, and then a report based on directory order would be a lie.
    foreach ($rel in @(
        "VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt",
        "VC\Auxiliary\Build\Microsoft.VCToolsVersion.v143.default.txt",
        "VC\Auxiliary\Build\Microsoft.VCToolsVersion.v142.default.txt"
    )) {
        $f = Join-Path $InstallPath $rel
        if (-not (Test-Path $f)) { continue }
        $v = Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue
        if ($v) {
            $v = "$v".Trim()
            if ($v -ne "") { return $v }
        }
    }
    return ""
}

function Sort-ByVersionDescending {
    param([array]$Items, [scriptblock]$KeySelector)
    # MSVC toolset numbers need real version ordering: as plain strings
    # "14.9" sorts above "14.51", which is backwards.
    return @($Items | Sort-Object -Property @{
        Expression = {
            $raw = & $KeySelector $_
            $v   = $null
            if ([Version]::TryParse("$raw", [ref]$v)) { $v } else { [Version]"0.0" }
        }
        Descending = $true
    })
}

function Select-ToolsetPath {
    param([string[]]$Paths, [string]$DefaultVersion)
    $items = @()
    foreach ($p in $Paths) {
        $v = ""
        if ($p -match '\\VC\\Tools\\MSVC\\([^\\]+)\\') { $v = $Matches[1] }
        $items += [PSCustomObject]@{ Path = $p; Version = $v }
    }
    if ($items.Count -eq 0) { return $null }

    if ($DefaultVersion) {
        $hit = @($items | Where-Object { $_.Version -eq $DefaultVersion }) | Select-Object -First 1
        if ($hit) {
            return [PSCustomObject]@{ Path = $hit.Path; Version = $hit.Version; Origin = "default.txt" }
        }
    }
    $hit = (Sort-ByVersionDescending -Items $items -KeySelector { param($i) $i.Version })[0]
    return [PSCustomObject]@{ Path = $hit.Path; Version = $hit.Version; Origin = "newest on disk" }
}

function Get-VsWhereClPaths {
    param([string]$OsArch, [string]$TargetArch)
    # vswhere 2.7+ resolves the toolset layout itself: -find globs inside every
    # matching instance, and -requires makes sure the C++ workload is actually
    # installed rather than just the shell of Visual Studio. Using Microsoft's
    # own resolver first means a future layout change is their problem, not
    # ours -- but it is one more process launch and it knows nothing about
    # pre-2017 installs, so the directory scan stays as the fallback.
    $vswhere = Find-VsWhere
    if (-not $vswhere) { return @() }

    $hostDirs = switch ($OsArch) {
        "arm64" { @("arm64", "x64", "x86") }
        "x86"   { @("x86") }
        default { @("x64", "x86") }
    }

    $out = @()
    foreach ($h in $hostDirs) {
        $pattern = "VC\Tools\MSVC\**\bin\Host" + $h + "\" + $TargetArch + "\cl.exe"
        try {
            $hits = & $vswhere -products '*' `
                        -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" `
                        -find $pattern 2>$null
        } catch {
            # vswhere older than 2.7 does not know -find; silently fall back.
            continue
        }
        foreach ($p in @($hits)) {
            $p = "$p".Trim()
            if ($p -ne "" -and (Test-Path $p)) { $out += $p }
        }
    }
    return @($out)
}

function Find-ClExe {
    param(
        [string]  $InstallPath,
        [string]  $OsArch,
        [string]  $TargetArch,
        [string[]]$VsWhereHits = @()
    )
    # Locate the one compiler that matters for this machine: host binaries
    # matching the OS architecture, producing code for the interpreter's
    # architecture.
    #
    # Host preference: native first, then the 32-bit host as a fallback (it is
    # present in every install and runs fine on x64/arm64).
    $hostDirs = switch ($OsArch) {
        "arm64" { @("arm64", "x64", "x86") }
        "x86"   { @("x86") }
        default { @("x64", "x86") }
    }

    $defaultToolset = Get-DefaultToolsetVersion -InstallPath $InstallPath
    $prefix         = $InstallPath.TrimEnd('\') + "\"
    $toolsRoot      = Join-Path $InstallPath "VC\Tools\MSVC"

    foreach ($h in $hostDirs) {
        # 1) What vswhere already resolved for this install, if anything.
        $hits = @($VsWhereHits | Where-Object {
            $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            $_ -match ('\\Host' + $h + '\\' + $TargetArch + '\\cl\.exe$')
        })
        $pick = $null
        $via  = ""
        if ($hits.Count -gt 0) {
            $pick = Select-ToolsetPath -Paths $hits -DefaultVersion $defaultToolset
            $via  = "vswhere -find"
        }

        # 2) Fallback: walk the documented layout ourselves.
        if (-not $pick -and (Test-Path $toolsRoot)) {
            $dirs = @(Get-ChildItem $toolsRoot -Directory -ErrorAction SilentlyContinue)
            $paths = @()
            foreach ($d in $dirs) {
                $cl = Join-Path $d.FullName ("bin\Host" + $h + "\" + $TargetArch + "\cl.exe")
                if (Test-Path $cl) { $paths += $cl }
            }
            if ($paths.Count -gt 0) {
                $pick = Select-ToolsetPath -Paths $paths -DefaultVersion $defaultToolset
                $via  = "directory scan"
            }
        }

        if ($pick) {
            return [PSCustomObject]@{
                ClExe         = $pick.Path
                ToolsVersion  = $pick.Version
                ToolsetOrigin = $pick.Origin
                FoundVia      = $via
                HostArch      = $h
                VcVarsTarget  = (Get-VcVarsTarget -HostArch $h -TargetArch $TargetArch -Legacy $false)
                Layout        = "VS2017+"
            }
        }
    }

    # VS2015 and older: the registry value points at ...\VC\ itself.
    $legacy = @(
        [PSCustomObject]@{ Rel = "bin\amd64\cl.exe";     HostArch = "x64"; Target = "x64" },
        [PSCustomObject]@{ Rel = "bin\x86_amd64\cl.exe"; HostArch = "x86"; Target = "x64" },
        [PSCustomObject]@{ Rel = "bin\cl.exe";           HostArch = "x86"; Target = "x86" },
        [PSCustomObject]@{ Rel = "bin\amd64_x86\cl.exe"; HostArch = "x64"; Target = "x86" }
    )
    foreach ($c in $legacy) {
        if ($c.Target -ne $TargetArch) { continue }
        if ($OsArch -eq "x86" -and $c.HostArch -ne "x86") { continue }
        $cl = Join-Path $InstallPath $c.Rel
        if (Test-Path $cl) {
            return [PSCustomObject]@{
                ClExe         = $cl
                ToolsVersion  = ""
                ToolsetOrigin = ""
                FoundVia      = "directory scan (legacy layout)"
                HostArch      = $c.HostArch
                VcVarsTarget  = (Get-VcVarsTarget -HostArch $c.HostArch -TargetArch $TargetArch -Legacy $true)
                Layout        = "legacy"
            }
        }
    }
    return $null
}

function Get-WindowsSdk {
    param([string]$TargetArch)
    # cl.exe alone cannot build anything: waf's compile step needs windows.h and
    # the import libraries. Newest kit that has both for this target wins.
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots",
        "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots"
    )) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props -or -not $props.KitsRoot10) { continue }
        $root    = ([string]$props.KitsRoot10).TrimEnd('\')
        $incRoot = Join-Path $root "Include"
        if (-not (Test-Path $incRoot)) { continue }
        $vers = @(Get-ChildItem $incRoot -Directory -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending)
        foreach ($v in $vers) {
            $hdr = Join-Path $v.FullName "um\windows.h"
            $lib = Join-Path $root ("Lib\" + $v.Name + "\um\" + $TargetArch + "\kernel32.lib")
            if ((Test-Path $hdr) -and (Test-Path $lib)) {
                return [PSCustomObject]@{ Version = $v.Name; Root = $root }
            }
        }
    }
    return $null
}

function Invoke-BatchProbe {
    param([string]$BatPath, [int]$TimeoutSec = 60)
    # Hardened child-process launch, for one reason each:
    #   * stdin is redirected and immediately closed -- a batch file that ever
    #     reads stdin (vcvarsall's SDK helpers have done this) otherwise blocks
    #     forever on an inherited console. waf does the same thing by passing
    #     stdin=DEVNULL to its own probe.
    #   * stdout/stderr are NOT redirected: the .bat sends everything to nul or
    #     a result file itself, so there are no pipes that can fill up and
    #     deadlock -- the exact failure mode already documented for this project.
    #   * a hard timeout with taskkill /T, so a wedged toolchain costs seconds
    #     instead of hanging the script indefinitely.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "cmd.exe"
    $psi.Arguments              = '/c "' + $BatPath + '"'
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardInput  = $true
    $proc           = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        $null = $proc.Start()
    } catch {
        return 98
    }
    try { $proc.StandardInput.Close() } catch { }
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch { }
        try { $proc.Kill() } catch { }
        return -1
    }
    return $proc.ExitCode
}

function Test-MsvcBuildEnv {
    param([string]$VcVarsAll, [string]$Target, [int]$TimeoutSec = 60)
    # waf's get_msvc_version() equivalent, used only as confirmation now:
    # source the environment batch file for real and start the compiler once.
    # Results come back through a file, not stdout, so nothing is piped.
    $stamp = [guid]::NewGuid().ToString("N")
    $bat   = Join-Path $env:TEMP ("msvcchk_" + $stamp + ".bat")
    $res   = Join-Path $env:TEMP ("msvcchk_" + $stamp + ".txt")
    $lines = @(
        '@echo off',
        ('call "' + $VcVarsAll + '" ' + $Target + ' <nul >nul 2>&1'),
        'if not defined INCLUDE exit /b 2',
        'if not defined LIB exit /b 3',
        'cl /nologo /help <nul >nul 2>&1',
        'if errorlevel 1 exit /b 4',
        ('> "'  + $res + '" echo TOOLS=%VCToolsVersion%'),
        ('>> "' + $res + '" echo SDK=%WindowsSDKVersion%'),
        'exit /b 0'
    )
    # OEM, not ASCII/UTF8: cmd.exe reads batch files in the console codepage,
    # so a non-ASCII install path would otherwise be mangled.
    Set-Content -LiteralPath $bat -Value $lines -Encoding Oem

    $out = @()
    try {
        $code = Invoke-BatchProbe -BatPath $bat -TimeoutSec $TimeoutSec
        if (Test-Path $res) {
            $out = @(Get-Content -LiteralPath $res -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item $bat -Force -ErrorAction SilentlyContinue
        Remove-Item $res -Force -ErrorAction SilentlyContinue
    }

    $tools = ""
    $sdk   = ""
    foreach ($line in $out) {
        if ($line -match '^TOOLS=(.*)$') { $tools = $Matches[1].Trim() }
        if ($line -match '^SDK=(.*)$')   { $sdk   = $Matches[1].Trim().TrimEnd('\') }
    }

    $reason = switch ($code) {
        0       { "" }
        -1      { "vcvarsall.bat did not finish within $TimeoutSec s -- probe aborted" }
        2       { "vcvarsall.bat ran but INCLUDE was not set" }
        3       { "vcvarsall.bat ran but LIB was not set" }
        4       { "cl.exe could not be started for target '$Target'" }
        98      { "could not launch cmd.exe for the probe" }
        default { "vcvarsall.bat failed for target '$Target' (exit $code)" }
    }

    return [PSCustomObject]@{
        Ok           = ($code -eq 0)
        Target       = $Target
        ToolsVersion = $tools
        SdkVersion   = $sdk
        Reason       = $reason
    }
}

function Resolve-MsvcToolchain {
    param(
        [array]  $Installs,
        [string] $TargetArch,
        [string] $OsArch,
        [string[]]$VsWhereHits = @(),
        [switch] $Deep
    )
    # Filesystem-only by default: for a given OS architecture and interpreter
    # bitness there is exactly one cl.exe worth looking for, and its path under
    # an install is fixed. That is a handful of Test-Path calls -- milliseconds,
    # no child processes, nothing that can hang.
    #
    # -Deep additionally runs the vcvarsall + cl probe once, on the winner only,
    # to catch an install whose files are present but broken.
    $sdk        = Get-WindowsSdk -TargetArch $TargetArch
    $lastReason = "no MSVC installation contains a cl.exe targeting $TargetArch"

    foreach ($inst in @($Installs)) {
        $cl = Find-ClExe -InstallPath $inst.Path -OsArch $OsArch `
                         -TargetArch $TargetArch -VsWhereHits $VsWhereHits
        if (-not $cl) {
            $lastReason = "$($inst.Name): no cl.exe targeting $TargetArch (C++ workload not installed?)"
            continue
        }
        if (-not $sdk) {
            $lastReason = "$($inst.Name): cl.exe found, but no Windows SDK with headers and $TargetArch libraries"
            continue
        }

        Write-OK "Compiler: $($inst.Name)"
        Write-Host "    cl.exe       : $($cl.ClExe)" -ForegroundColor Gray
        Write-Host "    found via    : $($cl.FoundVia)" -ForegroundColor Gray
        Write-Host "    host/target  : $($cl.HostArch) -> $TargetArch (vcvarsall: $($cl.VcVarsTarget))" -ForegroundColor Gray
        if ($cl.ToolsVersion) {
            $origin = if ($cl.ToolsetOrigin) { " ($($cl.ToolsetOrigin))" } else { "" }
            Write-Host "    MSVC toolset : $($cl.ToolsVersion)$origin" -ForegroundColor Gray
            if ($cl.ToolsetOrigin -eq "newest on disk") {
                Write-Host "                   note: Microsoft.VCToolsVersion.default.txt did not name an" -ForegroundColor Yellow
                Write-Host "                   installed toolset, so vcvarsall.bat may pick a different one" -ForegroundColor Yellow
            }
        }
        Write-Host "    Windows SDK  : $($sdk.Version)" -ForegroundColor Gray

        $verified = $false
        if ($Deep) {
            Write-Host "    verifying (vcvarsall + cl, up to 60 s) ... " -NoNewline -ForegroundColor Gray
            $sw   = [System.Diagnostics.Stopwatch]::StartNew()
            $test = Test-MsvcBuildEnv -VcVarsAll $inst.VcVarsAll -Target $cl.VcVarsTarget
            $sw.Stop()
            $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            if (-not $test.Ok) {
                Write-Host "FAILED ($secs s)" -ForegroundColor Yellow
                $lastReason = "$($inst.Name): $($test.Reason)"
                continue
            }
            Write-Host "OK ($secs s)" -ForegroundColor Green
            $verified = $true
        }

        return [PSCustomObject]@{
            Ok            = $true
            Name          = $inst.Name
            Version       = $inst.Version
            Path          = $inst.Path
            VcVarsAll     = $inst.VcVarsAll
            Source        = $inst.Source
            ClExe         = $cl.ClExe
            FoundVia      = $cl.FoundVia
            HostArch      = $cl.HostArch
            Target        = $cl.VcVarsTarget
            TargetArch    = $TargetArch
            ToolsVersion  = $cl.ToolsVersion
            ToolsetOrigin = $cl.ToolsetOrigin
            SdkVersion    = $sdk.Version
            Verified      = $verified
            Reason        = ""
        }
    }
    return [PSCustomObject]@{ Ok = $false; Reason = $lastReason }
}

function Show-BuildToolsHint {
    param([string]$Reason = "")
    Write-Host ""
    Write-Host "  MSVC Build Tools were not found (or are not usable)." -ForegroundColor Yellow
    if ($Reason -ne "") {
        Write-Host "  Detection result: $Reason" -ForegroundColor Gray
    }
    Write-Host "  To get a custom-compiled bootloader, install:" -ForegroundColor Gray
    Write-Host "    $BUILDTOOLS_URL" -ForegroundColor White
    Write-Host "  ...and pick the 'Desktop development with C++' workload" -ForegroundColor Gray
    Write-Host "  (MSVC v143 build tools + Windows 10/11 SDK), then re-run with -Method source." -ForegroundColor Gray
    Write-Host ""
}

function Show-Help {
    Write-Host "Usage: get_pyinstaller.cmd [options]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installs PyInstaller into the embedded Python located in .\python\ next to" -ForegroundColor Gray
    Write-Host "this script (created beforehand by the embed-Python installer)." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Method pip|source" -ForegroundColor White
    Write-Host "      Installation method. Supplying it disables ALL prompts -- the script" -ForegroundColor Gray
    Write-Host "      runs start to finish without stopping." -ForegroundColor Gray
    Write-Host "        pip    -- install the prebuilt wheel from PyPI. Fast, standard." -ForegroundColor Gray
    Write-Host "        source -- download the sdist and recompile the bootloader if MSVC" -ForegroundColor Gray
    Write-Host "                  Build Tools are present (fewer AV false positives, slower)." -ForegroundColor Gray
    Write-Host "                  If they are not, a warning is printed and the sdist is" -ForegroundColor Gray
    Write-Host "                  installed with its prebuilt bootloader instead." -ForegroundColor Gray
    Write-Host "      Omitted: the method is chosen interactively." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -Overwrite" -ForegroundColor White
    Write-Host "      Reinstall without asking when PyInstaller is already installed." -ForegroundColor Gray
    Write-Host "      Without it, an existing install triggers an [R]einstall/[C]ancel prompt" -ForegroundColor Gray
    Write-Host "      even when -Method was given." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -RequireCompiler" -ForegroundColor White
    Write-Host "      With -Method source: fail (exit 2) instead of silently falling back to" -ForegroundColor Gray
    Write-Host "      the prebuilt bootloader when no usable MSVC toolchain is found." -ForegroundColor Gray
    Write-Host "      Intended for CI, where a silent fallback would quietly drop the" -ForegroundColor Gray
    Write-Host "      antivirus mitigation the source build exists for." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -CheckTools" -ForegroundColor White
    Write-Host "      Diagnostics only: detect MSVC Build Tools and exit without installing" -ForegroundColor Gray
    Write-Host "      anything. Prints every installation found, how it was found (vswhere or" -ForegroundColor Gray
    Write-Host "      registry), its vcvarsall.bat, and the MSVC toolset / Windows SDK version" -ForegroundColor Gray
    Write-Host "      of the one that actually works. Exit 0 = usable, 2 = not usable." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -DeepCheck" -ForegroundColor White
    Write-Host "      Additionally verify the detected toolchain by actually running its" -ForegroundColor Gray
    Write-Host "      vcvarsall.bat and starting cl.exe once (a few seconds, 60 s timeout)." -ForegroundColor Gray
    Write-Host "      Detection is filesystem-based by default, which cannot tell a broken" -ForegroundColor Gray
    Write-Host "      install from a working one -- this can." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -NoWait" -ForegroundColor White
    Write-Host "      Do not wait for a keypress at the end, and do not pause the console" -ForegroundColor Gray
    Write-Host "      window on failure. Use for unattended runs." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  -Help, -h" -ForegroundColor White
    Write-Host "      Show this text and exit." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Exit codes:" -ForegroundColor Cyan
    Write-Host "  0  success (or user cancelled at the first prompt)" -ForegroundColor Gray
    Write-Host "  1  installation failed, or cancelled after an error" -ForegroundColor Gray
    Write-Host "  2  no usable MSVC toolchain (-RequireCompiler / -CheckTools)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  get_pyinstaller.cmd" -ForegroundColor White
    Write-Host "      Interactive: asks for the installation method." -ForegroundColor Gray
    Write-Host "  get_pyinstaller.cmd -Method source -Overwrite -NoWait" -ForegroundColor White
    Write-Host "      Fully unattended, e.g. when called from another .cmd script." -ForegroundColor Gray
    Write-Host "  get_pyinstaller.cmd -Method source -RequireCompiler -Overwrite -NoWait" -ForegroundColor White
    Write-Host "      Same, but fails loudly if the bootloader cannot be recompiled." -ForegroundColor Gray
    Write-Host "  get_pyinstaller.cmd -CheckTools -DeepCheck" -ForegroundColor White
    Write-Host "      Report what MSVC toolchain this machine has, verified by running it." -ForegroundColor Gray
    Write-Host ""
    Write-Host "MSVC Build Tools: $BUILDTOOLS_URL" -ForegroundColor Gray
    Write-Host ""
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
    param(
        [string]$PythonExe,
        [string]$ScriptDir,
        [bool]  $CompileBootloader = $true
    )

    # The upfront compiler check now happens in MAIN (Get-MsvcInstalls +
    # Resolve-MsvcToolchain) using waf's own discovery mechanism -- vswhere and
    # the registry, never PATH. $CompileBootloader is the result of that check:
    # $true  -> set PYINSTALLER_COMPILE_BOOTLOADER and actually rebuild;
    # $false -> install the same sdist without it, which uses the prebuilt
    #           bootloader binaries shipped inside the source archive.
    #
    # No portable-MSVC environment loading here: confirmed that waf discovers
    # MSVC via the Windows registry / VS Installer state, not via PATH/INCLUDE/
    # LIB -- so a manually configured, unregistered portable MSVC is invisible
    # to it no matter when or how the env vars are set. A real, registered
    # Visual Studio / Build Tools install is the only thing that works here.
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

    if ($CompileBootloader) {
        Write-Status "Compiling bootloader from source and installing..."
        Write-Host ""
        Write-Host "    This can take several minutes -- do not close this window" -ForegroundColor Green
        Write-Host ""
        $env:PYINSTALLER_COMPILE_BOOTLOADER = "1"
        try {
            $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
                "-m", "pip", "install", $tarball.FullName,
                "--no-warn-script-location", "--no-cache-dir"
            )
        } finally {
            Remove-Item Env:\PYINSTALLER_COMPILE_BOOTLOADER -ErrorAction SilentlyContinue
        }
    } else {
        Write-Status "Installing from the source archive (bootloader NOT recompiled)..." $tarball.Name
        $exit = Invoke-PipDirect -PythonExe $PythonExe -Arguments @(
            "-m", "pip", "install", $tarball.FullName,
            "--no-warn-script-location", "--no-cache-dir"
        )
    }

    if ($exit -ne 0) {
        Write-Fail "Source build/install failed (exit $exit)"
        # Deliberately NOT deleting $srcDir here: the fallback below reuses this
        # already-downloaded tarball instead of re-fetching from PyPI.
        return $false
    }

    Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($CompileBootloader) {
        Write-OK "PyInstaller installed from source (custom-compiled bootloader)"
    } else {
        Write-OK "PyInstaller installed from source (prebuilt bootloader from the sdist)"
    }
    return $true
}

# ==================== MAIN ====================
$pythonDir = Join-Path $ScriptDir "python"
$py        = Join-Path $pythonDir "python.exe"

Write-Host ""
Write-Host "==============================================" -ForegroundColor White
Write-Host " PyInstaller Installer (embedded Python)" -ForegroundColor White
Write-Host " version $version" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor White
Write-Host ""

# Help is answered before anything else is touched, so that it works even when
# .\python\ does not exist yet.
if ($Help) {
    Show-Help
    exit 0
}

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
$pyBits = Get-PythonBitness -PythonExe $py
Write-OK "Found: $verOut ($pyBits-bit)"

# The bootloader must match the interpreter, not the machine: a 32-bit embedded
# Python on a 64-bit box needs a 32-bit bootloader. The OS architecture only
# decides which host compiler binaries can run.
$osArch     = Get-OsArch
$targetArch = if ($pyBits -eq 64) { "x64" } else { "x86" }
Write-Status "Build target" "OS $osArch, Python $pyBits-bit -> compiler target $targetArch"

# Discovery now costs milliseconds (registry + Test-Path, no child processes),
# so the full answer is worked out upfront and the [S] menu entry can state it
# instead of just "something is installed". The status line still goes *before*
# the call: vswhere -legacy can take a moment.
Write-Status "Detecting MSVC Build Tools (waf-compatible discovery)..." "vswhere + registry"
$msvcInstalls = Get-MsvcInstalls
$toolchain    = $null

if ($msvcInstalls.Count -eq 0) {
    Write-Warn "No MSVC Build Tools found"
} else {
    foreach ($i in $msvcInstalls) {
        Write-Host "  - $($i.Name) [$($i.Version)] via $($i.Source)" -ForegroundColor White
        Write-Host "    $($i.VcVarsAll)" -ForegroundColor Gray
    }
    $vsWhereHits = Get-VsWhereClPaths -OsArch $osArch -TargetArch $targetArch
    $toolchain = Resolve-MsvcToolchain -Installs $msvcInstalls -TargetArch $targetArch `
                                       -OsArch $osArch -VsWhereHits $vsWhereHits -Deep:$DeepCheck
    if (-not $toolchain.Ok) { Write-Warn "Not usable: $($toolchain.Reason)" }
}

if ($CheckTools) {
    if (-not $toolchain -or -not $toolchain.Ok) {
        $reason = if ($toolchain) { $toolchain.Reason } else { "" }
        Show-BuildToolsHint -Reason $reason
        # No Read-Host here: the batch wrapper already pauses on a non-zero
        # exit code, and two "press any key" prompts in a row is just noise.
        exit 2
    }
    if ($toolchain.Verified) {
        Write-OK "Toolchain is usable (verified by running vcvarsall + cl)"
    } else {
        Write-OK "Toolchain is usable (use -DeepCheck to also run vcvarsall + cl)"
    }
    if (-not $NoWait) { Read-Host -Prompt "Press any key to continue" | Out-Null }
    exit 0
}

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

# Everything below runs without a single prompt when -Method was supplied.
$interactive = ($selMethod -eq "")

if ($interactive) {
    if ($toolchain -and $toolchain.Ok) {
        $toolsNote  = "compiler ready: $($toolchain.Name), target $targetArch"
        $toolsColor = "Green"
    } else {
        $toolsNote  = "no usable compiler -- bootloader will NOT be recompiled"
        $toolsColor = "Yellow"
    }
    Write-Host ""
    Write-Host "Installation method:" -ForegroundColor Cyan
    Write-Host "  [P] pip install       -- fast, standard prebuilt bootloader" -ForegroundColor White
    Write-Host "  [S] build from source -- compiles bootloader, fewer AV false positives, slower" -ForegroundColor White
    Write-Host "      $toolsNote" -ForegroundColor $toolsColor
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

$ok          = $false
$methodLabel = $selMethod

if ($selMethod -eq "source") {
    # Already resolved upfront -- nothing to re-run here.
    $compile = ($toolchain -and $toolchain.Ok)

    if (-not $compile) {
        $reason = if ($toolchain -and -not $toolchain.Ok) { $toolchain.Reason } else { "" }
        if ($RequireCompiler) {
            Write-Fail "-RequireCompiler was specified, but no usable MSVC toolchain is available"
            Show-BuildToolsHint -Reason $reason
            exit 2
        }
        Show-BuildToolsHint -Reason $reason
        Write-Warn "Continuing WITHOUT recompiling the bootloader."
        Write-Warn "PyInstaller will be installed from the source archive, but the bootloader"
        Write-Warn "binaries shipped inside it are the same prebuilt ones pip would give you --"
        Write-Warn "so this does NOT reduce antivirus false positives."
    }

    $ok = Install-FromSource -PythonExe $py -ScriptDir $ScriptDir -CompileBootloader $compile
    $methodLabel = if ($compile) { "source (bootloader compiled)" } else { "source (prebuilt bootloader)" }

    if (-not $ok) {
        $srcDir = Join-Path $ScriptDir "pyinstaller_src"
        $sdist  = Get-ChildItem $srcDir -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue |
                  Select-Object -First 1
        $sdistPath = $(if ($sdist) { $sdist.FullName } else { "" })

        if ($interactive) {
            Write-Host ""
            Write-Host "  [F] Fall back to the prebuilt bootloader instead" -ForegroundColor White
            Write-Host "  [O] Open the Build Tools download page and exit" -ForegroundColor White
            Write-Host "  [C] Cancel" -ForegroundColor White
            Write-Host ""
            while ($true) {
                $choice = (Read-Host "Select [F/O/C]").Trim().ToUpper()
                if ($choice -eq "O") {
                    Show-BuildToolsHint
                    try { Start-Process $BUILDTOOLS_URL } catch { }
                    exit 1
                }
                if ($choice -eq "C") { exit 1 }
                if ($choice -eq "F") {
                    $ok = Install-ViaPip -PythonExe $py -SdistPath $sdistPath
                    Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
                    $methodLabel = "pip (fallback after failed source build)"
                    break
                }
                Write-Host "  Invalid input, try again" -ForegroundColor Yellow
            }
        } else {
            Write-Warn "Source install failed -- falling back to the prebuilt bootloader (non-interactive)"
            $ok = Install-ViaPip -PythonExe $py -SdistPath $sdistPath
            Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            $methodLabel = "pip (fallback after failed source build)"
        }
    }
} else {
    $ok = Install-ViaPip -PythonExe $py
    $methodLabel = "pip (prebuilt bootloader)"
}

if (-not $ok) { exit 1 }

$finalVer = Get-PyInstallerVersion -PythonExe $py

Write-Host ""
Write-Host "==================== COMPLETE ====================" -ForegroundColor Green
Write-Host "Python      : $py"          -ForegroundColor White
Write-Host "PyInstaller : $finalVer"    -ForegroundColor White
Write-Host "Method      : $methodLabel" -ForegroundColor White
if ($methodLabel -eq "source (bootloader compiled)" -and $toolchain) {
    Write-Host "Compiler    : $($toolchain.Name) [$($toolchain.Target)]" -ForegroundColor White
    if ($toolchain.ToolsVersion) {
        Write-Host "Toolset/SDK : $($toolchain.ToolsVersion) / $($toolchain.SdkVersion)" -ForegroundColor White
    }
}
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
if (-not $NoWait) { Read-Host -Prompt "Press any key to continue" }
