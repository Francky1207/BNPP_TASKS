@echo off
REM ===========================================================
REM  Lance la batterie de test complete du package
REM  Un seul rapport texte est produit a la fin.
REM ===========================================================

setlocal
cd /d "%~dp0"

echo.
echo   Deblocage des fichiers...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path .\*.ps1,.\*.psm1 -ErrorAction SilentlyContinue | Unblock-File"

echo   Lancement de la batterie de test...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Test-ToutLePackage.ps1"

echo.
echo   Termine. Consultez le fichier RAPPORT_TESTS_*.txt cree dans ce dossier.
pause

endlocal
