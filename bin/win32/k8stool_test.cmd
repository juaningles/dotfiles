@echo off
REM Run the PowerShell script with proper argument handling
powershell -ExecutionPolicy Bypass -Command "& { & '%~dpn0.ps1' --query 'utopia-ingestion-dev' --name 'utopia-dev-lab-eastus-kc3' }"
exit /b %ERRORLEVEL%