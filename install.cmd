@echo off
rem Double-click to install. Optional argument: pc or notebook
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
