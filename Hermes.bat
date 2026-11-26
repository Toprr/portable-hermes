@echo off
rem Start Hermes Agent: opens the Hermes window (Open Hermes / Update / Repair / Restart / Stop) and starts
rem Hermes in the background right away (Webapp, messaging bots, remote access). Closing the window without
rem using a button stops it again. Direct start without the window: scripts\start.ps1 (opens the Webapp in
rem the default browser).
rem conhost --headless: the launcher gets no console window. "-WindowStyle Hidden" alone cannot hide it when
rem Windows Terminal is the default console (it takes the window over and an empty tab stays open).
start "" conhost.exe --headless powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0scripts\launcher.ps1"
