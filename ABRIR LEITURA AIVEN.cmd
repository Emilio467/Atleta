@echo off
setlocal
set "ATLETA_PYTHON=%~dp0.venv-lab\Scripts\python.exe"
if not exist "%ATLETA_PYTHON%" (
    echo Prepare o ambiente Python conforme LEIA PRIMEIRO.txt.
    pause
    exit /b 1
)
title Atleta IP - Aiven ao vivo
"%ATLETA_PYTHON%" -X utf8 -u "%~dp0tools\ler_aiven.py"
