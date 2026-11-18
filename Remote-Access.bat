@echo off
rem Turn on remote access to the Webapp from your other devices (phone, tablet, laptop) over Tailscale:
rem downloads Tailscale into tools\tailscale (nothing is installed), signs this Hermes in to your tailnet
rem (opens a sign-in link), publishes the Webapp at https://hermes.<your-tailnet>.ts.net and asks for a
rem Webapp password if none is set yet. Turn it off again: scripts\tailscale.ps1 disable
title Hermes Agent - Remote access
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tailscale.ps1" login
if errorlevel 1 goto end
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\set-webapp-password.ps1" -IfMissing
echo.
echo Then restart Hermes (Restart button in the Hermes window, or Stop-Hermes.bat and Hermes.bat).
:end
pause
