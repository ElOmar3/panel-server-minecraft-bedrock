@echo off
title Lanzador - Minecraft Bedrock Server
cd /d "%~dp0"
echo Iniciando servidor...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar.ps1"
pause