@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo [WiSensing] Python environment not found.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" "scripts\wisensing_launcher.py" --stop
if errorlevel 1 pause
endlocal
