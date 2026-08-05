@echo off
setlocal EnableDelayedExpansion

chdir /d "%~dp0"

set "progname=token_extractor"

set "SCRIPTDIR=%~dp0"
set "SCRIPTDIR=%SCRIPTDIR:~0,-1%"
set "PS1FILE=%TEMP%\pydownloader_%RANDOM%.ps1"
set "PYTHON_PATH=%SCRIPTDIR%\python"
set "PYTHON_SCRIPTS=%PYTHON_PATH%\Scripts"
rem set "PATH=%PYTHON_PATH%;%PYTHON_SCRIPTS%;%PATH%"
set "PYTHON_EXE=%PYTHON_PATH%\python.exe"

for /F "delims=" %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"
	set "RED=%ESC%[31m"
	set "GREEN=%ESC%[32m"
	set "YELLOW=%ESC%[33m"
	set "BLUE=%ESC%[34m"
	set "MAGENTA=%ESC%[35m"
	set "CYAN=%ESC%[36m"
	set "WHITE=%ESC%[37m"

	set "LRED=%ESC%[91m"
	set "LGREEN=%ESC%[92m"
	set "LYELLOW=%ESC%[93m"
	set "LBLUE=%ESC%[94m"
	set "LMAGENTA=%ESC%[95m"
	set "LCYAN=%ESC%[96m"

	set "RESET=%ESC%[0m"

call:main_build || exit /b 1
exit /b

:check_python
if exist "%PYTHON_EXE%" (
	echo.
	echo.%LGREEN%Embedded Python found:%RESET%
	echo."%PYTHON_EXE%"
	exit /b 0
) else (
	echo.
	echo.%LRED%Embedded Python NOT found:%RESET%"%PYTHON_EXE%"
	echo.%LRED%program aborted%RESET%
	echo.
	pause
	exit /b 1
)
exit /b

:main_build
echo.
echo.%LGREEN%Python2exe script builder for %progname%%RESET%
echo.Script analyse .py and compile .exe stub
echo.Checking environments...

call:check_python||exit /b 1

	if exist "%SCRIPTDIR%\build\" (rmdir /S /Q "%SCRIPTDIR%\build")
	if exist "%SCRIPTDIR%\dist\"  (rmdir /S /Q "%SCRIPTDIR%\dist")
	echo.
	echo.%LCYAN%[*] Compile %progname%.exe from %progname%.py%RESET%
	
	set Q="
	if exist "%SCRIPTDIR%\icon.ico" (
		set "icon=--icon %Q%icon.ico%Q%"
	) else (
		set "icon="
	)
	
	if exist "%SCRIPTDIR%\%progname%.spec" (
		echo.
		echo.%LGREEN%[+] %progname% spec file found, use it%RESET%
		echo.
		echo.%LCYAN%PyInstaller log:%RESET%
		"%PYTHON_EXE%" -m PyInstaller --clean "%SCRIPTDIR%\%progname%.spec"
	) else (
		echo.
		echo.%LYELLOW%[*] spec file not found, compile %progname%.exe from internal spec file%RESET%
		echo.%LCYAN%PyInstaller log:%RESET%
		"%PYTHON_EXE%" -m PyInstaller --onefile --noupx %icon% --name=%progname% "%progname%.py"
	)
	if %errorlevel% neq 0 (
		echo.
		echo.%LRED%[-] Error compile %progname%.exe%RESET%
		echo. Press any key to exit
		pause
		exit /b 1
	)
	echo.
	echo.%LCYAN%[*] Copy resulting .exe to !SCRIPTDIR! folder%RESET%
	copy /b /y "%SCRIPTDIR%\dist\%progname%.exe" "%SCRIPTDIR%\%progname%.exe">nul 2>&1
	echo.
	echo.%LCYAN%[*] Delete temporary folder%RESET%
	if exist "%SCRIPTDIR%\build\" (rmdir /S /Q "%SCRIPTDIR%\build")
	if exist "%SCRIPTDIR%\dist\"  (rmdir /S /Q "%SCRIPTDIR%\dist")
	echo.
	echo.%LGREEN%[+] Done compile %progname%.exe%RESET%
	echo.
	pause

exit /b 0