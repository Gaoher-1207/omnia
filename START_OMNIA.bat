@echo off
setlocal
title OMNIA - Startup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Shehwaar\omnia_ui\integration\start_omnia.ps1"
if errorlevel 1 (
    echo OMNIA startup failed. Review the error above and the service windows.
    pause
    exit /b 1
)
endlocal
