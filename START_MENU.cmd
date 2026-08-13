@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0menu.ps1"
  exit /b %errorlevel%
)

where powershell.exe >nul 2>&1
if %errorlevel%==0 (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0menu.ps1"
  exit /b %errorlevel%
)

echo [ERREUR] PowerShell est introuvable.
pause
exit /b 1
