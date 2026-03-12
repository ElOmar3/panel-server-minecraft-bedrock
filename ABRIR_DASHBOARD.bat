@echo off
title Iniciando Dashboard de Minecraft...
color 0B

echo ===================================================
echo     Verificando dependencias para el Dashboard...
echo ===================================================

:: Mueve el directorio de ejecucion a la ubicacion del archivo .bat
cd /d "%~dp0"

:: Comprueba si Python esta instalado en el sistema
python --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    color 0C
    echo.
    echo [ERROR] No se pudo encontrar Python en el sistema.
    echo Asegurate de tener instalado Python 3.8 o superior y 
    echo de haber marcado la opcion "Add python.exe to PATH" durante la instalacion.
    echo.
    echo Puedes descargarlo desde: https://www.python.org/downloads/
    echo.
    pause
    exit /b
)

:: Si Python existe, lanza el script
echo.
echo [OK] Python detectado. Iniciando el panel graphico...
start "" pythonw server_dashboard.py

:: Si el script falla inmediatamente (ej. faltan librerias raras), usar python normal para debug
IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Ocurrio un problema al iniciar el dashboard de forma silenciosa.
    echo Intentando abrir en modo consola para ver errores...
    python server_dashboard.py
    pause
)

exit
