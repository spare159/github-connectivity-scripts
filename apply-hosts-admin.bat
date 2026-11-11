@echo off
REM Double-click this file. It requests administrator approval (UAC) by itself,
REM then writes the GitHub hosts mapping. No right-click menu needed.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running with administrator rights.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-github-hosts.ps1"
echo.
echo === github.com entries in hosts ===
findstr /i "github.com" "%windir%\System32\drivers\etc\hosts"
echo.
echo Done. If GitHub stops working later, just double-click this file again
echo to pick a new reachable IP.
echo.
pause
