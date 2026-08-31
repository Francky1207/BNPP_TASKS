##############################################################
# NOM          : PS_ET_01_Check_CRE_Files_Status_RO.ps1
# CATEGORIE    : 10 - ETL / CHAÎNE DE TRAITEMENT
# PRIORITE     : P0
# AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
# VERSION      : 1.0 — Calibré pour répertoires Windows partagés
##############################################################
#
# OBJECTIF :
#   Vérifier l'état des fichiers CRE (Excel/CSV) avant ou après
#   un traitement DATA STUDIO. Répondre à la question :
#   "Les fichiers source sont-ils présents, récents et non vides ?"
#
# TYPE        : READ ONLY — aucune modification de fichier
# RISQUE      : FAIBLE — lecture seule sur le système de fichiers
#
# PERMISSIONS :
#   Lecture sur le répertoire partagé Windows contenant les CRE
#
# PARAMÈTRES :
#   $RepCRE           — chemin du répertoire CRE (UNC ou local)
#   $ExtensionsFiltres — extensions à analyser ('*.xlsx','*.csv')
#   $AgeMaxHeures     — alerte si fichier non modifié depuis X heures
#   $TailleMinOctets  — alerte si fichier plus petit que X octets
#
# UTILISATION :
#   .\PS_ET_01_Check_CRE_Files_Status_RO.ps1
#   .\PS_ET_01_Check_CRE_Files_Status_RO.ps1 -RepCRE "\\serveur\partage\CRE" -AgeMaxHeures 24
#
# RÉSULTATS :
#   Liste des fichiers avec taille, date, statut
#   Alertes si fichier absent, vide, ou trop ancien
#   Résumé global avec compte des anomalies
#
# ETAPE SUIVANTE :
#   Si fichier absent → alerter l'équipe source / DATA STUDIO
#   Si fichier vide   → fichier corrompu ou traitement incomplet en amont
#   Si fichier ancien → le traitement source n'a pas tourné
##############################################################

param(
    [string]$RepCRE           = "C:\CRE",              # ← Adapter à votre chemin
    [string[]]$ExtensionsFiltres = @("*.xlsx","*.csv","*.xls"),
    [int]$AgeMaxHeures        = 24,                    # Alerte si > 24h sans modification
    [long]$TailleMinOctets    = 1024                   # Alerte si < 1 Ko
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Horodatage = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PS_ET_01 — CONTROLE FICHIERS CRE — $Horodatage" -ForegroundColor Cyan
Write-Host "Répertoire : $RepCRE" -ForegroundColor Cyan
Write-Host "Extensions : $($ExtensionsFiltres -join ', ')" -ForegroundColor Cyan
Write-Host "Âge max    : $AgeMaxHeures heures" -ForegroundColor Cyan
Write-Host "Taille min : $TailleMinOctets octets" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ============================================================
# VÉRIFICATION 1 — Le répertoire existe-t-il ?
# ============================================================
Write-Host "`n--- VÉRIFICATION 1 : EXISTENCE DU RÉPERTOIRE ---" -ForegroundColor Yellow

if (-not (Test-Path $RepCRE)) {
    Write-Host "🔴 RÉPERTOIRE INTROUVABLE : $RepCRE" -ForegroundColor Red
    Write-Host "   Vérifier l'accès réseau ou le chemin UNC" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Répertoire accessible : $RepCRE" -ForegroundColor Green

# ============================================================
# VÉRIFICATION 2 — Lister et analyser les fichiers
# ============================================================
Write-Host "`n--- VÉRIFICATION 2 : ÉTAT DES FICHIERS CRE ---" -ForegroundColor Yellow

$LimiteAge = (Get-Date).AddHours(-$AgeMaxHeures)
$NbAlertes = 0
$NbFichiersOK = 0
$TotalTailleMo = 0

$Fichiers = @()
foreach ($ext in $ExtensionsFiltres) {
    $Fichiers += Get-ChildItem -Path $RepCRE -Filter $ext -Recurse -ErrorAction SilentlyContinue
}

if ($Fichiers.Count -eq 0) {
    Write-Host "🔴 AUCUN FICHIER CRE TROUVÉ dans $RepCRE" -ForegroundColor Red
    Write-Host "   Extensions cherchées : $($ExtensionsFiltres -join ', ')" -ForegroundColor Red
    $NbAlertes++
} else {
    Write-Host "Fichiers trouvés : $($Fichiers.Count)" -ForegroundColor Cyan
    Write-Host ""

    foreach ($Fichier in $Fichiers | Sort-Object LastWriteTime -Descending) {
        $TailleMo      = [Math]::Round($Fichier.Length / 1MB, 2)
        $TotalTailleMo += $TailleMo
        $AgeHeures     = [Math]::Round(((Get-Date) - $Fichier.LastWriteTime).TotalHours, 1)
        $Statut        = @()
        $Couleur       = "Green"

        # Contrôle taille
        if ($Fichier.Length -lt $TailleMinOctets) {
            $Statut += "🔴 VIDE/TROP PETIT ($($Fichier.Length) octets)"
            $Couleur  = "Red"
            $NbAlertes++
        }

        # Contrôle âge
        if ($Fichier.LastWriteTime -lt $LimiteAge) {
            $Statut += "🟡 ANCIEN (${AgeHeures}h)"
            if ($Couleur -ne "Red") { $Couleur = "Yellow" }
            $NbAlertes++
        }

        # Contrôle accès (fichier ouvert en exclusif par un autre processus ?)
        $FichierLocked = $false
        try {
            $stream = [System.IO.File]::Open($Fichier.FullName, 'Open', 'Read', 'Read')
            $stream.Close()
            $stream.Dispose()
        } catch {
            $Statut += "🔴 FICHIER VERROUILLÉ (ouvert par un autre processus)"
            $Couleur  = "Red"
            $FichierLocked = $true
            $NbAlertes++
        }

        if ($Statut.Count -eq 0) {
            $Statut += "✅ OK"
            $NbFichiersOK++
        }

        # Affichage
        $Ligne = "{0,-50} {1,8} Mo  {2,20}  Age: {3,6}h  {4}" -f `
            $Fichier.Name,
            $TailleMo,
            $Fichier.LastWriteTime.ToString("yyyy-MM-dd HH:mm"),
            $AgeHeures,
            ($Statut -join " | ")

        Write-Host $Ligne -ForegroundColor $Couleur
    }
}

# ============================================================
# VÉRIFICATION 3 — Espace disque disponible
# ============================================================
Write-Host "`n--- VÉRIFICATION 3 : ESPACE DISQUE ---" -ForegroundColor Yellow

try {
    $Drive = Split-Path -Qualifier $RepCRE
    if ($Drive -match "^\\\\") {
        # Chemin UNC — espace disque du partage
        $PSDrive = Get-PSDrive | Where-Object { $_.Root -like "$Drive*" } | Select-Object -First 1
        if ($PSDrive) {
            $LibreMo = [Math]::Round($PSDrive.Free / 1MB)
            Write-Host "Espace libre (partage réseau) : $LibreMo Mo" -ForegroundColor $(if ($LibreMo -lt 1024) {"Red"} else {"Green"})
        } else {
            Write-Host "⚠️ Espace disque non calculable (chemin UNC)" -ForegroundColor Yellow
        }
    } else {
        $DisqueInfo = Get-PSDrive -Name $Drive.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($DisqueInfo) {
            $LibreMo = [Math]::Round($DisqueInfo.Free / 1MB)
            $TotalMo = [Math]::Round(($DisqueInfo.Free + $DisqueInfo.Used) / 1MB)
            $PctLibre = [Math]::Round($LibreMo / $TotalMo * 100)
            $CouleurEspace = if ($PctLibre -lt 10) { "Red" } elseif ($PctLibre -lt 20) { "Yellow" } else { "Green" }
            Write-Host "Disque ${Drive} — Libre : $LibreMo Mo / $TotalMo Mo ($PctLibre% libre)" -ForegroundColor $CouleurEspace
            if ($PctLibre -lt 10) { $NbAlertes++ }
        }
    }
} catch {
    Write-Host "⚠️ Impossible de lire l'espace disque : $_" -ForegroundColor Yellow
}

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "RÉSUMÉ — PS_ET_01 — $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "Fichiers analysés : $($Fichiers.Count)" -ForegroundColor White
Write-Host "Fichiers OK       : $NbFichiersOK" -ForegroundColor Green
Write-Host "Alertes détectées : $NbAlertes" -ForegroundColor $(if ($NbAlertes -gt 0) {"Red"} else {"Green"})
Write-Host "Taille totale     : $([Math]::Round($TotalTailleMo,1)) Mo" -ForegroundColor White

if ($NbAlertes -eq 0) {
    Write-Host "`n✅ TOUS LES FICHIERS CRE SONT EN ORDRE" -ForegroundColor Green
    Write-Host "   DATA STUDIO peut démarrer le traitement" -ForegroundColor Green
} else {
    Write-Host "`n🔴 $NbAlertes ALERTE(S) DÉTECTÉE(S) — TRAITEMENT À VÉRIFIER" -ForegroundColor Red
    Write-Host "   Résoudre les alertes avant de lancer DATA STUDIO" -ForegroundColor Red
}

Write-Host "================================================================" -ForegroundColor Cyan

# Code retour utilisable dans un script orchestrateur
exit $NbAlertes
