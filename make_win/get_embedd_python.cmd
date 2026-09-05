<# : batch cmd
@echo off
setlocal EnableDelayedExpansion

set "version=26.0902"
set "SCRIPTDIR=%~dp0"
set "SCRIPTDIR=%SCRIPTDIR:~0,-1%"

set ARGS= %*
if defined ARGS set "ARGS=%ARGS:"=\"%"
if defined ARGS set "ARGS=%ARGS:'=''%"

powershell -NoProfile -ExecutionPolicy Bypass -c ^"$ScriptDir='%SCRIPTDIR%'; Invoke-Expression ('^& {' + (get-content -raw '%~f0') + '} %ARGS%')"

set "RC=%errorlevel%"
if not "%RC%"=="0" pause

exit /b %RC%
#>

param(
    [string]$PyVer = "",
    [string]$Arch  = ""
)

$DEFAULT_PACKAGES = @(
    "pyinstaller"
)

if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }

Add-Type -AssemblyName System.IO.Compression.FileSystem

[Net.ServicePointManager]::SecurityProtocol    = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
[Net.ServicePointManager]::DefaultConnectionLimit = 8

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

function Test-TcpConnect {
    param([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 5000)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        try { $tcp.EndConnect($ar) } catch { }
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Download-File {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Description = "File",
        [int]   $Retries     = 3
    )
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Status "Retry $attempt/$Retries..." $Url
            Start-Sleep -Seconds 2
        }
        try {
            if (Test-Path $Dest) { Remove-Item $Dest -Force }
            Write-Status "Downloading $Description..." $Url

            $req              = [System.Net.HttpWebRequest]::Create($Url)
            $req.Timeout      = 120000
            $req.ReadWriteTimeout = 120000
            $resp             = $req.GetResponse()
            $totalBytes       = $resp.ContentLength
            $stream           = $resp.GetResponseStream()
            $fs               = [System.IO.File]::Create($Dest)
            $buf              = New-Object byte[] 65536
            $downloaded       = [long]0
            $lastPct          = -1

            while ($true) {
                $read = $stream.Read($buf, 0, $buf.Length)
                if ($read -le 0) { break }
                $fs.Write($buf, 0, $read)
                $downloaded += $read
                if ($totalBytes -gt 0) {
                    $pct = [int]($downloaded * 100 / $totalBytes)
                    if ($pct -ne $lastPct -and $pct % 10 -eq 0) {
                        $dl  = [math]::Round($downloaded / 1MB, 1)
                        $tot = [math]::Round($totalBytes  / 1MB, 1)
                        Write-Host "`r    $pct% -- $dl MB / $tot MB   " -NoNewline -ForegroundColor Gray
                        $lastPct = $pct
                    }
                }
            }
            $fs.Close()
            $stream.Close()
            $resp.Close()
            Write-Host ""

            if ((Test-Path $Dest) -and (Get-Item $Dest).Length -gt 0) { return $true }
            throw "File is empty or missing after download"
        } catch {
            if (Test-Path $Dest) { Remove-Item $Dest -Force -ErrorAction SilentlyContinue }
            Write-Fail "Attempt $attempt failed: $($_.Exception.Message)"
        }
    }
    return $false
}

function Get-EmbedBuilds {
    param([string]$BaseUrl)
    Write-Status "Fetching version list..." $BaseUrl
    try {
        $page = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 30
    } catch {
        throw "Cannot fetch python.org index: $($_.Exception.Message)"
    }
    $versions = @(
        $page.Links |
        Where-Object { $_.href -match '^(3\.\d+\.\d+)/$' } |
        ForEach-Object { $Matches[1] } |
        Sort-Object { [Version]$_ } -Descending
    )
    if ($versions.Count -eq 0) { throw "No Python 3.x versions found on python.org" }

    $builds = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total  = $versions.Count
    $cur    = 0
    foreach ($ver in $versions) {
        $cur++
        Write-Host "`r    Scanning $cur/$total : $ver   " -NoNewline -ForegroundColor Gray
        try {
            $vpage = Invoke-WebRequest -Uri "$BaseUrl$ver/" -UseBasicParsing -TimeoutSec 10
            foreach ($link in $vpage.Links) {
                if ($link.href -match '^python-(\d+\.\d+\.\d+)-embed-(amd64|win32)\.zip$') {
                    $builds.Add([PSCustomObject]@{
                        Version  = $Matches[1]
                        Arch     = $Matches[2]
                        FileName = $link.href
                        Url      = "$BaseUrl$ver/$($link.href)"
                    })
                }
            }
        } catch { }
    }
    Write-Host ""
    return $builds
}

function Select-FromList {
    param([string]$Title, [string[]]$Items)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host "  [$($i+1)] $($Items[$i])" -ForegroundColor White
    }
    Write-Host ""
    while ($true) {
        $input = Read-Host "Enter number (1-$($Items.Count))"
        $n = 0
        if ([int]::TryParse($input, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
            return $n - 1
        }
        Write-Host "  Invalid input, try again" -ForegroundColor Yellow
    }
}

function Test-PyConfigValues {
    param([string]$Version, [string]$Arch, [string]$Source)
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "${Source}: version must look like '3.12.4' (got '$Version')"
    }
    if ($Arch -notmatch '^(amd64|win32)$') {
        throw "${Source}: arch must be 'amd64' or 'win32' (got '$Arch')"
    }
    return [PSCustomObject]@{
        Version = $Version
        Arch    = $Arch
    }
}

function Read-PyConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $cfg = $raw | ConvertFrom-Json
    } catch {
        throw "pyconfig.json is not valid JSON: $($_.Exception.Message)"
    }

    if (-not $cfg.version -or -not $cfg.arch) {
        throw "pyconfig.json must contain both 'version' and 'arch' fields"
    }

    return Test-PyConfigValues -Version ([string]$cfg.version) -Arch ([string]$cfg.arch) -Source "pyconfig.json"
}

function Read-CliConfig {
    param([string]$PyVer, [string]$Arch)
    if ($PyVer -eq "" -and $Arch -eq "") { return $null }
    if ($PyVer -eq "" -or  $Arch -eq "") {
        throw "Both -PyVer and -Arch must be specified together on the command line"
    }
    return Test-PyConfigValues -Version $PyVer -Arch $Arch -Source "command-line arguments"
}

function Write-PyConfig {
    param([string]$Path, [string]$Version, [string]$Arch)
    try {
        $obj  = [PSCustomObject]@{ version = $Version; arch = $Arch }
        $json = $obj | ConvertTo-Json
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
        Write-OK "pyconfig.json updated: Python $Version [$Arch]"
    } catch {
        Write-Fail "Could not write pyconfig.json: $($_.Exception.Message)"
    }
}

function Select-BuildInteractive {
    param([array]$Builds)
    $uniqVer = @($Builds | Select-Object -ExpandProperty Version -Unique |
                 Sort-Object { [Version]$_ } -Descending)
    $vi = Select-FromList -Title "Select Python version:" -Items $uniqVer
    $selVer = $uniqVer[$vi]

    $verBuilds = @($Builds | Where-Object { $_.Version -eq $selVer })
    $uniqArch  = @($verBuilds | Select-Object -ExpandProperty Arch -Unique | Sort-Object)
    if ($uniqArch.Count -eq 1) {
        $selArch = $uniqArch[0]
        Write-Host "  Architecture: $selArch (only available)" -ForegroundColor Gray
    } else {
        $ai = Select-FromList -Title "Select architecture:" -Items $uniqArch
        $selArch = $uniqArch[$ai]
    }

    return $verBuilds | Where-Object { $_.Arch -eq $selArch } | Select-Object -First 1
}

function Invoke-Python {
    param([string]$PythonExe, [string]$Arguments, [string]$StatusText)
    Write-Status $StatusText
    $p = Start-Process -FilePath $PythonExe -ArgumentList $Arguments `
                       -NoNewWindow -Wait -PassThru
    $script:_lastErr = ""
    return $p.ExitCode
}

function Install-Pip {
    param([string]$PythonDir, [string]$DownloadDir)
    $py         = Join-Path $PythonDir "python.exe"
    $getPipDest = Join-Path $DownloadDir "get-pip.py"

    $ok = Download-File -Url "https://bootstrap.pypa.io/get-pip.py" `
                        -Dest $getPipDest -Description "get-pip.py"

    if ($ok) {
        foreach ($f in (Get-ChildItem $PythonDir -Filter "*._pth" -File -ErrorAction SilentlyContinue)) {
            Rename-Item $f.FullName "$($f.FullName).bak" -Force -ErrorAction SilentlyContinue
        }
        $exit = Invoke-Python -PythonExe $py `
                    -Arguments "`"$getPipDest`" --no-warn-script-location --no-cache-dir" `
                    -StatusText "Installing pip via get-pip.py..."
        if ($exit -eq 0) { Write-OK "pip installed via get-pip.py"; return $true }
        Write-Fail "get-pip.py failed: $($script:_lastErr)"
        Write-Status "Trying pip wheel fallback..."
    } else {
        Write-Fail "get-pip.py unavailable, trying pip wheel..."
    }

    Write-Status "Fetching pip wheel URL..." "pypi.org/pypi/pip/json"
    try {
        $json   = Invoke-WebRequest -Uri "https://pypi.org/pypi/pip/json" -UseBasicParsing -TimeoutSec 15
        $whlUrl = ($json.Content | ConvertFrom-Json).urls |
                  Where-Object { $_.filename -match '^pip-[\d.]+-py3-none-any\.whl$' } |
                  Select-Object -ExpandProperty url -First 1
    } catch { $whlUrl = "" }

    if (-not $whlUrl) { Write-Fail "Failed to get pip wheel URL from PyPI"; return $false }

    $whlDest = Join-Path $DownloadDir "pip.whl"
    $ok = Download-File -Url $whlUrl -Dest $whlDest -Description "pip wheel"
    if (-not $ok) { Write-Fail "Failed to download pip wheel"; return $false }

    Write-Status "Unpacking pip wheel..."
    $siteDir = Join-Path $PythonDir "site-packages"
    New-Item $siteDir -ItemType Directory -Force | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($whlDest, $siteDir)
    } catch {
        Write-Fail "Failed to unpack pip wheel: $($_.Exception.Message)"
        return $false
    }

    $pthFile = Get-ChildItem $PythonDir -Filter "*._pth*" -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
    if ($pthFile) {
        $pthPath = $pthFile.FullName -replace '\.bak$', ''
        $txt = Get-Content $pthFile.FullName -Encoding UTF8
        $txt = @($txt | ForEach-Object {
            if ($_ -match '^#\s*import site') { "import site" } else { $_ }
        })
        if (-not ($txt -contains "import site"))    { $txt = @("import site") + $txt }
        if (-not ($txt -contains "site-packages"))  { $txt = $txt + @("site-packages") }
        [System.IO.File]::WriteAllLines($pthPath, $txt, (New-Object Text.UTF8Encoding($false)))
    }

    $exit = Invoke-Python -PythonExe $py -Arguments "-m pip --version --no-cache-dir" `
                -StatusText "Verifying pip..."
    if ($exit -ne 0) { Write-Fail "pip verification failed: $($script:_lastErr)"; return $false }
    Write-OK "pip installed via wheel"
    return $true
}

function Read-Requirements {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [string[]]@() }
    return @(Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue |
             Where-Object { $_ -and $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") } |
             ForEach-Object { $_.Trim() })
}

function Install-Requirements {
    param([string]$PythonDir, [string]$RequirementsFile)
    $py   = Join-Path $PythonDir "python.exe"
    $exit = Invoke-Python -PythonExe $py `
                -Arguments "-m pip install -r `"$RequirementsFile`" --no-warn-script-location --no-cache-dir" `
                -StatusText "Installing packages from requirements.txt..."
    if ($exit -ne 0) {
        Write-Fail "requirements.txt install failed (exit $exit): $($script:_lastErr)"
        return $false
    }
    Write-OK "Packages installed from requirements.txt"
    return $true
}

function Install-Packages {
    param([string]$PythonDir, [string[]]$Packages)
    if ($Packages.Count -eq 0) { return $true }
    $py      = Join-Path $PythonDir "python.exe"
    $pkgList = $Packages -join " "
    $exit    = Invoke-Python -PythonExe $py `
                   -Arguments "-m pip install $pkgList --no-warn-script-location --no-cache-dir" `
                   -StatusText "Installing packages: $pkgList"
    if ($exit -ne 0) { Write-Fail "Package install failed (exit $exit): $($script:_lastErr)"; return $false }
    Write-OK "Packages installed: $pkgList"
    return $true
}

# ==================== MAIN ====================
$downloadDir      = Join-Path $ScriptDir "download"
$pythonDir        = Join-Path $ScriptDir "python"
$baseUrl          = "https://www.python.org/ftp/python/"
$configFile       = Join-Path $ScriptDir "pyconfig.json"
$requirementsFile = Join-Path $ScriptDir "requirements.txt"

$reqPackages     = Read-Requirements -Path $requirementsFile
$hasRequirements = $reqPackages.Count -gt 0

Write-Host ""
Write-Host "Python Embed Installer (console)" -ForegroundColor Cyan
if ($hasRequirements) {
    Write-Host "Packages: from requirements.txt ($($reqPackages.Count) entries)" -ForegroundColor White
} else {
    Write-Host "Packages: $($DEFAULT_PACKAGES -join ', ')" -ForegroundColor White
}
Write-Host ""

try {
    Write-Status "Checking connection..." "www.python.org:443"
    if (-not (Test-TcpConnect -HostName "www.python.org")) {
        Write-Fail "No internet connection or python.org is unreachable"
        exit 1
    }
    Write-OK "Connection OK"

    try {
        $cliConfig  = Read-CliConfig -PyVer $PyVer -Arch $Arch
        $jsonConfig = Read-PyConfig  -Path $configFile
    } catch {
        Write-Fail $_.Exception.Message
        exit 1
    }

    $pyConfig = $null
    if ($cliConfig) {
        $pyConfig = $cliConfig
        Write-OK "Using command-line arguments: Python $($pyConfig.Version) [$($pyConfig.Arch)]"
        if ($jsonConfig) {
            Write-Host "  (pyconfig.json is also present but ignored -- command-line arguments take priority)" -ForegroundColor Gray
        }
    } elseif ($jsonConfig) {
        $pyConfig = $jsonConfig
        Write-OK "pyconfig.json found: Python $($pyConfig.Version) [$($pyConfig.Arch)]"
    }

    foreach ($dir in @($downloadDir, $pythonDir)) {
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction Stop }
    }
    New-Item $downloadDir -ItemType Directory -Force | Out-Null

    $builds = Get-EmbedBuilds -BaseUrl $baseUrl
    if ($builds.Count -eq 0) {
        Write-Fail "No embed builds found on python.org"
        exit 1
    }

    if ($pyConfig) {
        $sel = $builds | Where-Object { $_.Version -eq $pyConfig.Version -and $_.Arch -eq $pyConfig.Arch } |
               Select-Object -First 1
        if (-not $sel) {
            Write-Fail "Requested Python $($pyConfig.Version) [$($pyConfig.Arch)] not found on python.org"
            $availArch = @($builds | Where-Object { $_.Version -eq $pyConfig.Version } |
                           Select-Object -ExpandProperty Arch -Unique)
            if ($availArch.Count -gt 0) {
                Write-Host "  Available architectures for $($pyConfig.Version): $($availArch -join ', ')" -ForegroundColor Yellow
            } else {
                Write-Host "  Version $($pyConfig.Version) was not found on python.org at all" -ForegroundColor Yellow
            }

            Write-Host ""
            while ($true) {
                $choice = (Read-Host "[S]elect version manually / [C]ancel").Trim().ToUpper()
                if ($choice -eq "C") { exit 1 }
                if ($choice -eq "S") { break }
                Write-Host "  Invalid input, try again" -ForegroundColor Yellow
            }
            $sel = Select-BuildInteractive -Builds $builds
            Write-PyConfig -Path $configFile -Version $sel.Version -Arch $sel.Arch
        }
    } else {
        $sel = Select-BuildInteractive -Builds $builds
    }
    $zipDest = Join-Path $downloadDir $sel.FileName
    $ok = Download-File -Url $sel.Url -Dest $zipDest `
                        -Description "Python $($sel.Version) [$($sel.Arch)]"
    if (-not $ok) { Write-Fail "Python ZIP download failed"; exit 1 }
    Write-OK "Downloaded: $([math]::Round((Get-Item $zipDest).Length / 1MB, 1)) MB"

    Write-Status "Extracting..." "To: $pythonDir"
    New-Item $pythonDir -ItemType Directory -Force | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipDest, $pythonDir)
    } catch {
        Write-Fail "Extraction failed: $($_.Exception.Message)"
        exit 1
    }
    if (-not (Test-Path (Join-Path $pythonDir "python.exe"))) {
        Write-Fail "python.exe not found after extraction"
        exit 1
    }
    Write-OK "Extracted to: $pythonDir"

    $ok = Install-Pip -PythonDir $pythonDir -DownloadDir $downloadDir
    if (-not $ok) { exit 1 }

    if ($hasRequirements) {
        $ok = Install-Requirements -PythonDir $pythonDir -RequirementsFile $requirementsFile
    } else {
        $ok = Install-Packages -PythonDir $pythonDir -Packages $DEFAULT_PACKAGES
    }
    if (-not $ok) { exit 1 }

    Remove-Item $downloadDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "==================== COMPLETE ====================" -ForegroundColor Green
    Write-Host "Location : $pythonDir"                              -ForegroundColor White
    Write-Host "Version  : $($sel.Version) [$($sel.Arch)]"          -ForegroundColor White
    if ($hasRequirements) {
        Write-Host "Installed: pip + $($reqPackages.Count) package(s) from requirements.txt" -ForegroundColor White
    } else {
        Write-Host "Installed: pip + $($DEFAULT_PACKAGES -join ', ')" -ForegroundColor White
    }
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host ""
	Read-Host -Prompt "Press any key to continue"

} catch {
    Write-Fail "FATAL ERROR: $($_.Exception.Message)"
    exit 1
}
