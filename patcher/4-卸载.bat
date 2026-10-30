@echo off
chcp 65001 >nul
set "NODE=%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
set "INS=C:\Users\Administrator.DESKTOP-1B8MNPO\Documents\deepseek-harness\default-workspace\chatbox-unbound\install.mjs"
"%NODE%" "%INS%" --uninstall
echo.
echo Done. Config restored, skill and MCP entry removed.
pause
