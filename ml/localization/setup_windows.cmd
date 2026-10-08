@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_windows.ps1" %*
set "CSI_SETUP_EXIT=%ERRORLEVEL%"
if not "%CSI_SETUP_NO_PAUSE%"=="1" pause
exit /b %CSI_SETUP_EXIT%
