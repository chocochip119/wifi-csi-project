@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo [WiSensing] .venv\Scripts\python.exe was not found.
  echo Please set up the Python Backend environment first.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" "scripts\wisensing_launcher.py" --ps-host 10.10.20.41
if errorlevel 1 (
  echo.
  echo [WiSensing] Startup failed. See messages above and .wisensing_runtime logs.
  pause
)
endlocal
