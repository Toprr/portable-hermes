@echo off
rem Stop Hermes (the background gateway: Webapp, Discord, scheduled jobs).
title Hermes Agent - Stop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop.ps1"
pause
