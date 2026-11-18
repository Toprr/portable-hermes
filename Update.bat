@echo off
rem Update Hermes Agent to the newest official version (data and settings are kept).
title Hermes Agent - Update
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update.ps1" %*
pause
