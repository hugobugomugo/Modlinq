@echo off
REM run from the repo root

cd mod_manager_flutter

echo [1/3] building flutter windows release
flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo error: flutter build failed
    pause
    exit /b %ERRORLEVEL%
)

echo [2/3] locating inno setup
set INNO_SETUP_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe
if not exist "%INNO_SETUP_PATH%" (
    echo error: inno setup 6 not found
    echo https://jrsoftware.org/isdl.php
    pause
    exit /b 1
)

cd ..

echo [3/3] building installer
"%INNO_SETUP_PATH%" "windows_installer\setup.iss"
if %ERRORLEVEL% NEQ 0 (
    echo error: installer build failed
    pause
    exit /b %ERRORLEVEL%
)

echo done: windows_installer\output\
pause
