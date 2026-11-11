@echo off
REM Copy the GitHub authorize URL first, then double-click this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-auth-in-fixed-edge.ps1"
pause
