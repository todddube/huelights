@echo off
REM Create Windows Task Scheduler service for Modern Hue Control Panel

echo 🪟 Creating Windows Task Scheduler service for Modern Hue Control Panel...

REM Get current directory
set "CURRENT_DIR=%CD%"
echo    Directory: %CURRENT_DIR%

REM Check for Python executable
set "PYTHON_PATH=python"
if exist ".venv\Scripts\python.exe" (
    set "PYTHON_PATH=%CURRENT_DIR%\.venv\Scripts\python.exe"
    echo    Python: %PYTHON_PATH%
) else (
    echo    Python: %PYTHON_PATH% (system Python)
)

REM Create logs directory
if not exist "logs" mkdir logs

REM Create the scheduled task
echo Creating scheduled task...

schtasks /create /tn "Modern Hue Control Panel" /tr "\"%PYTHON_PATH%\" \"%CURRENT_DIR%\start_modern.py\" run --host 0.0.0.0 --port 8501" /sc onstart /ru "%USERNAME%" /rl highest /f

if %errorlevel% equ 0 (
    echo ✅ Task created successfully!
    echo.
    echo 🚀 To start the service:
    echo    schtasks /run /tn "Modern Hue Control Panel"
    echo.
    echo 🛑 To stop the service:
    echo    taskkill /f /im python.exe
    echo.
    echo 📊 To check status:
    echo    schtasks /query /tn "Modern Hue Control Panel"
    echo.
    echo 🗑️  To delete the task:
    echo    schtasks /delete /tn "Modern Hue Control Panel" /f
    echo.
    echo 🔄 The service will automatically start when Windows boots.
) else (
    echo ❌ Failed to create task. Make sure you're running as Administrator.
    pause
    exit /b 1
)

pause