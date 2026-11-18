@echo off
rem First-time setup or repair of the portable Hermes Agent.
title Hermes Agent - Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1" %*
pause
