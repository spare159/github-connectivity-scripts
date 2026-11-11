@echo off
REM Fallback: launch Edge with github.com pinned to a verified working IP.
REM No administrator rights needed. Uses a separate Edge profile.
start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --host-resolver-rules="MAP github.com 20.87.245.0" --user-data-dir="%TEMP%\gh-edge" https://github.com/login
