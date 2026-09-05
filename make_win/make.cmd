<# : batch cmd
@echo off
setlocal EnableExtensions EnableDelayedExpansion

chdir /d "%~dp0"

set "progname=token_extractor"

set "SCRIPTDIR=%~dp0"
set "SCRIPTDIR=%SCRIPTDIR:~0,-1%"
set "PYTHON_PATH=%SCRIPTDIR%\python"
set "PYTHON_SCRIPTS=%PYTHON_PATH%\Scripts"
set "PYTHON_EXE=%PYTHON_PATH%\python.exe"
set "PROGNAME_EXE=%SCRIPTDIR%\%progname%.exe"
set "ICON_ICO=%PYTHON_PAT%\Lib\site-packages\PyInstaller\bootloader\images\icon-console.ico"
set "pyinstaller_src=%SCRIPTDIR%\pyinstaller_src"

set "ARGS="!PROGNAME_EXE!" %*"
if defined ARGS set "ARGS=%ARGS:"=\"%"
if defined ARGS set "ARGS=%ARGS:'=''%"
call:Init
call:main_build || exit /b 1
exit /b

:Init
for /F "delims=" %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"
set "LRED=%ESC%[91m"
set "LGREEN=%ESC%[92m"
set "LYELLOW=%ESC%[93m"
set "LBLUE=%ESC%[94m"
set "LMAGENTA=%ESC%[95m"
set "LCYAN=%ESC%[96m"
set "LWHITE=%ESC%[97m"
set "RESET=%ESC%[0m"
exit /b

:check_python
if exist "%PYTHON_EXE%" (
	echo.
	echo.%LGREEN%[+] Embedded Python found:%RESET%
	echo.    %PYTHON_EXE%
	exit /b 0
) else (
	echo.
	echo.%LRED%[-] Embedded Python NOT found:%RESET%"%PYTHON_EXE%"
	echo.%LRED%program aborted%RESET%
	echo.
	pause
	exit /b 1
)
exit /b

:main_build
echo.
echo.%LWHITE%Python2exe script builder for %progname%
echo.Script analyse .py and compile .exe stub%RESET%
echo.
echo.%LCYAN%[*] Checking environments...%RESET%

call:check_python||exit /b 1
	
	if exist "%SCRIPTDIR%\build\" (rmdir /S /Q "%SCRIPTDIR%\build")
	if exist "%SCRIPTDIR%\dist\"  (rmdir /S /Q "%SCRIPTDIR%\dist")
	echo.
	echo.%LCYAN%[*] Compile %progname%.exe from %progname%.py%RESET%
	set "icon="
	set Q="
	if exist "%SCRIPTDIR%\icon.ico" (set "icon=--icon %Q%icon.ico%Q%")
	
	if defined icon (
		echo.
		echo.%LGREEN%[+] icon file found, use it%RESET%
		echo.    %SCRIPTDIR%\icon.ico
	) else (
		echo.
		echo.%LYELLOW%[-] icon file not found, compile %progname%.exe from default pyInstaller icon%RESET%
	)
	if exist "%SCRIPTDIR%\%progname%.spec" (
		echo.
		echo.%LGREEN%[+] %progname% spec file found, use it%RESET%
		echo.    %SCRIPTDIR%\%progname%.spec
		echo.
		echo.%LCYAN% PyInstaller log:%RESET%
		"%PYTHON_EXE%" -m PyInstaller --clean "%SCRIPTDIR%\%progname%.spec"
	) else (
		echo.
		echo.%LYELLOW%[-] spec file not found, compile %progname%.exe from internal spec file%RESET%
		echo.%LCYAN%   PyInstaller log:%RESET%
		
		"%PYTHON_EXE%" -m PyInstaller --onefile --noupx %icon% --name=%progname% "%progname%.py"
	)
	if %errorlevel% neq 0 (
		echo.
		echo.%LRED%[-] Error compile %progname%.exe%RESET%
		echo.
		echo. %LWHITE%Press any key to clean temporary folders and exit%RESET%
		echo.
		pause
		echo.%LCYAN%[*] Delete temporary folder%RESET%
			if exist "%SCRIPTDIR%\build\" (rmdir /S /Q "%SCRIPTDIR%\build")
			if exist "%SCRIPTDIR%\dist\"  (rmdir /S /Q "%SCRIPTDIR%\dist")
		timeout /t 5
		exit /b 1
	)
	echo.
	echo.%LCYAN%[*] Copy resulting .exe to !SCRIPTDIR! folder%RESET%
	copy /b /y "%SCRIPTDIR%\dist\%progname%.exe" "%SCRIPTDIR%\%progname%.exe">nul 2>&1
	echo.
	echo.%LCYAN%[*] Strip Rich PE header (reduces antivirus false positives)%RESET%
	
	powershell -c ^"Invoke-Expression ('^& {' + (get-content -raw '%~f0') + '} %ARGS%')"

	echo.
	echo.%LCYAN%[*] Delete temporary folder%RESET%
	if exist "%SCRIPTDIR%\build\" (rmdir /S /Q "%SCRIPTDIR%\build")
	if exist "%SCRIPTDIR%\dist\"  (rmdir /S /Q "%SCRIPTDIR%\dist")
	if exist "%pyinstaller_src%" (rmdir /S /Q "%pyinstaller_src%")
	echo.
	echo.%LGREEN%[+] Done compile %progname%.exe%RESET%
	echo.
	timeout /t 5
exit /b 0

#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
)

# The MSVC linker embeds a "Rich" header with build-environment metadata
# into every PE it produces; some AV/YARA rules fingerprint off it, on top
# of the stock PyInstaller bootloader binary.
# Zeroing the Rich header out removes that signal too.
Write-Host "$ExePath"
function Find-ByteSequence {
    param([byte[]]$Haystack, [byte[]]$Needle, [int]$Start = 0, [int]$End = -1)
    if ($End -lt 0) { $End = $Haystack.Length }
    $limit = $End - $Needle.Length
    for ($i = $Start; $i -le $limit; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Host "[!] Strip Rich header: file not found: $ExePath" -ForegroundColor Red
    exit 1
}

$data = [System.IO.File]::ReadAllBytes($ExePath)

$richBytes = [byte[]](0x52, 0x69, 0x63, 0x68)  # "Rich"
$rich = Find-ByteSequence -Haystack $data -Needle $richBytes

if ($rich -lt 0) {
    Write-Host "[*] Rich header not found, skipping" -ForegroundColor Gray
    exit 0
}

$ck        = [BitConverter]::ToUInt32($data, $rich + 4)
$dansValue = [uint32]0x536E6144 -bxor $ck
$dansBytes = [BitConverter]::GetBytes($dansValue)
$ds        = Find-ByteSequence -Haystack $data -Needle $dansBytes -End $rich

if ($ds -lt 0) {
    Write-Host "[*] DanS marker not found, skipping" -ForegroundColor Gray
    exit 0
}

for ($i = $ds; $i -lt $rich + 8; $i++) { $data[$i] = 0 }
[System.IO.File]::WriteAllBytes($ExePath, $data)
Write-Host "[+] Stripped Rich header: offset $ds..$($rich + 8)" -ForegroundColor Green