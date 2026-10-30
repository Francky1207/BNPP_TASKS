# PROGRAMME TRAITEMENT COMPTE DATA STUDIO

$ErrorActionPreference = "Stop"

$DS_DISK = "D:"
$DS_PATH = "$DS_DISK\applis\data\DataStudio40 Server"

$DS_CLIENT_PATH = "$DS_PATH\dtstud_c.exe"
$DS_SERVER_PATH = "$DS_PATH\datastudsrv.exe"

$WORKSPACE = "RUPIL2"
$DS_USER = "Admin"
$PROJECT_NAME = "TESTS"

$Secret1Path = "E:\TRAITEMENT\RUPIL2\KELIA\TEST_20260917\TEST CRYPTO MDP\passphrase.dat"

# 1. Verification des fichiers
if (-not (Test-Path $DS_CLIENT_PATH)) {
    throw "Executable DataStudio introuvable : $DS_CLIENT_PATH"
}

if (-not (Test-Path $Secret1Path)) {
    throw "Fichier mot de passe introuvable : $Secret1Path"
}

# 2. Recuperation du mot de passe chiffré
$Passphrase = Get-Content $Secret1Path |
    Select-Object -First 1 |
    ConvertTo-SecureString

# 3. Conversion en pointeur memoire BSTR / Unicode
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)

try {
    # 4. Recuperation de la chaine en clair
    $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    # 5. Lancement DataStudio
    Set-Location $DS_PATH

    Write-Host "Debut $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Write-Host "LANCEMENT DATASTUDIO SERVER SUR LE WORKSPACE $WORKSPACE DU PROJET $PROJECT_NAME"

    $arguments = @(
        "CONNECT=$WORKSPACE"
        "USER=$DS_USER"
        "PASSWORD=$plainText"
        "CMDPROJECT=$PROJECT_NAME"
    )

    & $DS_CLIENT_PATH @arguments
    $LaunchExitCode = $LASTEXITCODE

    Write-Host "FIN DU TRAITEMENT DATASTUDIO"
    Write-Host "Code retour lancement : $LaunchExitCode"
}
finally {
    # 6. Demande d'arret du serveur DataStudio
    Write-Host "DEMANDE D'ARRET DU SERVEUR DATASTUDIO"

    try {
        & $DS_CLIENT_PATH "-close" "CONNECT=$WORKSPACE"
        $CloseExitCode = $LASTEXITCODE

        Write-Host "SERVEUR ARRETE"
        Write-Host "Code retour fermeture : $CloseExitCode"
    }
    catch {
        Write-Host "ERREUR FERMETURE DATASTUDIO : $($_.Exception.Message)"
        $CloseExitCode = 1
    }

    # 7. Nettoyage du mot de passe en memoire
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $plainText = $null
    $Passphrase = $null

    Write-Host "Fin $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
}

if ($LaunchExitCode -ne 0) {
    throw "Erreur lors du lancement DataStudio. Code retour : $LaunchExitCode"
}

if ($CloseExitCode -ne 0) {
    throw "Erreur lors de la fermeture DataStudio. Code retour : $CloseExitCode"
}
