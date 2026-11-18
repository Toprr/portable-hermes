@echo off
rem Hermes in the terminal (TUI).
title Hermes Agent - Terminal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" -Ui tui
if errorlevel 1 pause
