@echo off
setlocal

rem Wrapper for build.ps1 - allows double-click or cmd invocation.
rem Usage: build.bat [module] [-Clean]   module: app / server / all

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
