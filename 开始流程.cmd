@echo off
chcp 65001 >nul
title Laptop Setup Launcher

:: 检查是否管理员运行
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

set "SourcePath=%~dp0."
set "TargetPath=C:\temp"
set "ScriptName=装软件.ps1"
set "ScriptPath=%TargetPath%\%ScriptName%"

echo Source: %SourcePath%
echo Target: %TargetPath%
echo.

if not exist "%TargetPath%" (
    echo Creating C:\temp ...
    mkdir "%TargetPath%"
)

echo Copying files from "%SourcePath%" to "%TargetPath%" ...
robocopy "%SourcePath%" "%TargetPath%" /E /R:2 /W:2

if %errorlevel% GEQ 8 (
    echo.
    echo Copy failed.
    pause
    exit /b 1
)

echo.
echo Copy completed.

if not exist "%ScriptPath%" (
    echo.
    echo PowerShell script not found: %ScriptPath%
    pause
    exit /b 1
)

echo.
echo Starting PowerShell setup script...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ScriptPath%"

echo.
echo Setup script finished.
pause