@echo off
rem Set or change the Webapp username/password (asked when the Webapp is opened from another device).
title Hermes Agent - Webapp password
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\set-webapp-password.ps1"
echo.
echo Then restart Hermes: Stop-Hermes.bat, then Hermes.bat
pause
