@echo off
chcp 65001 >nul
set "INS=%~dp0..\install.mjs"
set "RUN=node"
where node >nul 2>nul
if errorlevel 1 set "RUN=%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
"%RUN%" "%INS%" --status 
pause
