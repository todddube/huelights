@echo off
REM Hue Front Room Startup Script for Windows
REM This batch file runs the front room lighting startup script

echo Starting Hue Front Room Lighting...
echo.

cd /d "%~dp0"

REM Check if uv is available, otherwise use python directly
where uv >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Using uv to run startup script...
    uv run python front_room_startup.py %*
) else (
    echo Using python to run startup script...
    python front_room_startup.py %*
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Error occurred! Check the logs for details.
    echo Press any key to exit...
    pause >nul
) else (
    echo.
    echo Startup complete! Lights should now be active.
    timeout /t 3 >nul
)