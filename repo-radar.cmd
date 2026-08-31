@echo off
setlocal
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0repo-radar.ps1" -Path "%CD%" -Open
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0repo-radar.ps1" -Path "%~1" -Open
)
if errorlevel 1 (
  echo.
  echo Repo Radar could not generate the report.
  pause
)

