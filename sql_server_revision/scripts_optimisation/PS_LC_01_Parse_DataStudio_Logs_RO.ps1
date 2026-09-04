<#
NOM: PS_LC_01_Parse_DataStudio_Logs_RO.ps1 | CAT: 13-LOGS | P0
TYPE: READ ONLY | PERMS: Lecture fichier log
OBJET: Parser et filtrer les logs DATA STUDIO (.txt/.log)
       Extraire : erreurs, durees, etapes, anomalies
       Adapte la regex $PatternHeure si le format de votre log differe
       NOTE: Envoyer un extrait de log reel pour calibrer precisement ce script
PARAM: $CheminLog, $AfficherErreurs, $AfficherDurees, $DureeSeuilSecondes
#>
param(
    [string]$CheminLog              = "C:\Logs\datastudio.log",   # <- Adapter
    [bool]$AfficherErreurs          = $true,
    [bool]$AfficherDurees           = $true,
    [int]$DureeSeuilSecondes        = 30,   # alerter si etape > 30 secondes
    [bool]$AfficherResume           = $true
)

if (-not (Test-Path $CheminLog)) {
    Write-Host "ERREUR: Fichier introuvable : $CheminLog" -ForegroundColor Red
    exit 1
}

$lignes = Get-Content $CheminLog -Encoding UTF8
$nbTotal = $lignes.Count
$erreurs = @(); $etapes = @()

# Patterns a ajuster selon le format reel du log DATA STUDIO
# Envoyer un extrait du log pour calibrage precis
$patternErreur  = 'ERROR|ERREUR|EXCEPTION|FAILED|ECHEC|ORA-|Msg \d+|SqlException'
$patternDebut   = '(?i)debut|start|starting|demarrage|lancement'
$patternFin     = '(?i)fin|end|completed|termine|duree|elapsed|secondes?|minutes?'
$patternHeure   = '\d{2}[:/]\d{2}[:/]\d{2}'  # format HH:MM:SS

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PS_LC_01 — ANALYSE LOG DATA STUDIO" -ForegroundColor Cyan
Write-Host "Fichier : $CheminLog" -ForegroundColor Cyan
Write-Host "Taille  : $nbTotal lignes" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$numLigne = 0
foreach ($ligne in $lignes) {
    $numLigne++

    # Detecter les erreurs
    if ($AfficherErreurs -and $ligne -match $patternErreur) {
        $erreurs += [PSCustomObject]@{ Ligne = $numLigne; Texte = $ligne }
    }

    # Detecter les lignes de duree / performance
    if ($AfficherDurees -and ($ligne -match $patternDebut -or $ligne -match $patternFin)) {
        $etapes += [PSCustomObject]@{ Ligne = $numLigne; Texte = $ligne }
    }
}

# Afficher les erreurs
if ($AfficherErreurs) {
    Write-Host "`n--- ERREURS DETECTEES ($($erreurs.Count)) ---" -ForegroundColor Red
    $erreurs | ForEach-Object {
        Write-Host ("L{0,6}: {1}" -f $_.Ligne, $_.Texte) -ForegroundColor Red
    }
}

# Afficher les etapes / durees
if ($AfficherDurees) {
    Write-Host "`n--- ETAPES / PERFORMANCES ($($etapes.Count) lignes) ---" -ForegroundColor Yellow
    $etapes | Select-Object -First 50 | ForEach-Object {
        Write-Host ("L{0,6}: {1}" -f $_.Ligne, $_.Texte) -ForegroundColor White
    }
    if ($etapes.Count -gt 50) { Write-Host "... (+ $($etapes.Count - 50) lignes — augmenter le limite)" }
}

# Resume
if ($AfficherResume) {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "RESUME LOG : $CheminLog" -ForegroundColor Cyan
    Write-Host "Lignes totales : $nbTotal" -ForegroundColor White
    Write-Host "Erreurs        : $($erreurs.Count)" -ForegroundColor $(if ($erreurs.Count -gt 0) {"Red"} else {"Green"})
    Write-Host "Etapes traces  : $($etapes.Count)" -ForegroundColor White
    Write-Host "" 
    Write-Host "NOTE: Envoyer un extrait reel du log pour calibrer ce parser" -ForegroundColor Yellow
    Write-Host "      (patterns d'heure, de debut/fin, de duree specifiques DATA STUDIO)" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
}
