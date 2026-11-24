@echo off
setlocal
set "ATLETA_PYTHON=%~dp0.venv-lab\Scripts\pythonw.exe"
if not exist "%ATLETA_PYTHON%" set "ATLETA_PYTHON=%~dp0..\.venv-lab\Scripts\pythonw.exe"
if not exist "%ATLETA_PYTHON%" (
    echo Ambiente Python do projeto nao encontrado.
    echo Consulte o README.md para instalar as dependencias em .venv-lab.
    pause
    exit /b 1
)
start "" /D "%~dp0" "%ATLETA_PYTHON%" "%~dp0laboratorio\painel\app.py"
