@echo off
set SCRIPT=%~dp0unlimited-clipboard.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
