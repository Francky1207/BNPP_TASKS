@echo off
REM ===========================================================
REM  Lanceur de la boite a outils ETL
REM  Double-cliquez sur ce fichier pour demarrer le programme.
REM  Aucun droit administrateur necessaire.
REM ===========================================================

setlocal
cd /d "%~dp0"

echo.
echo   Deblocage des fichiers (necessaire apres un telechargement)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path .\*.ps1,.\*.psm1 -ErrorAction SilentlyContinue | Unblock-File"

echo   Demarrage de l interface...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Start-Toolkit.ps1"

if errorlevel 1 (
  echo.
  echo   Le programme s est termine avec une erreur.
  pause
)

endlocal
