@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>&1
if not %errorlevel%==0 (
  echo [ERREUR] PowerShell 7 est introuvable.
  echo [REQUIS] PowerShell 7.6.4 minimum ^(Core, x64, pwsh.exe^).
  echo [INFO] Windows PowerShell 5.1 n'est pas utilise comme fallback par ce depot.
  pause
  exit /b 1
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0menu.ps1"
exit /b %errorlevel%
