<#
================================================================================
 PSToolkit-Recettes.ps1 - Exemples prets a l'emploi
================================================================================

 CE FICHIER N'EST PAS FAIT POUR ETRE EXECUTE EN ENTIER.
 C'est un recueil de recettes : copiez la section qui vous interesse.

 Chargement prealable du module :
     Import-Module C:\CRE\PSToolkit.psm1 -Force
     Get-Command -Module PSToolkit          # liste les 42 fonctions
     Get-Help Import-CsvFast -Full          # aide detaillee d'une fonction

================================================================================
#>

Import-Module "$PSScriptRoot\PSToolkit.psm1" -Force


# ##############################################################################
# RECETTE 1 : Decouvrir un fichier inconnu
# ##############################################################################
# Situation : on vous transmet un fichier, vous ne savez rien de sa structure.

$f = 'C:\Data\export_inconnu.csv'

Get-FileEncoding  -Path $f                       # UTF8-BOM ? ANSI ?
Get-CsvDelimiter  -Path $f                       # ; ou , ou TAB ?
Measure-FileLine  -Path $f                       # combien de lignes, quelle taille
Get-FileHead      -Path $f -Count 5              # a quoi ressemblent les donnees

# Profilage complet : taux de remplissage, valeurs distinctes, type probable
Import-CsvFast -Path $f | Get-DataProfile | Format-Table -AutoSize

# Si le fichier est enorme, n'en charger qu'un echantillon
Import-CsvFast -Path $f -First 1000 | Get-DataProfile | Format-Table -AutoSize


# ##############################################################################
# RECETTE 2 : Nettoyer et typer un CSV avant chargement DWH
# ##############################################################################
# Probleme : Import-Csv renvoie tout en texte -> "100" + 5 = "1005"

$schema = @{
    ClientId    = 'int'
    Montant     = 'decimal'
    DateVente   = 'datetime'
    EstActif    = 'bool'
}

$donnees = Import-CsvFast -Path 'C:\Data\ventes.csv' |
           ConvertTo-TypedObject -Schema $schema

# Maintenant les calculs fonctionnent reellement
($donnees | Measure-Object -Property Montant -Sum).Sum


# ##############################################################################
# RECETTE 3 : Controler la qualite avant d'alimenter le datawarehouse
# ##############################################################################
# Principe : detecter les problemes AVANT le chargement, pas apres.

$regles = @{
    CodeClient = @{ Required = $true; Unique = $true; Pattern = '^CLI\d{4}$'; MaxLength = 10 }
    Montant    = @{ Required = $true; MinValue = 0; MaxValue = 1000000 }
    Statut     = @{ Required = $true; AllowedValues = @('Valide', 'Invalide', 'EnAttente') }
    Email      = @{ Pattern = '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' }
}

$violations = Import-CsvFast -Path 'C:\Data\clients.csv' |
              Test-DataQuality -Rules $regles

if ($violations) {
    Write-Log -Message ("{0} violation(s) detectee(s)" -f @($violations).Count) -Level ERROR
    $violations | Export-CsvFast -Path 'C:\Data\rapport_qualite.csv'
    $violations | Group-Object Regle | Select-Object Name, Count | Format-Table
}
else {
    Write-Log -Message 'Controle qualite : aucun probleme' -Level SUCCESS
}


# ##############################################################################
# RECETTE 4 : Comparer deux extractions (avant / apres migration)
# ##############################################################################
# Cas classique : verifier qu'une migration n'a rien casse.

$avant = Import-CsvFast -Path 'C:\Data\avant_migration.csv'
$apres = Import-CsvFast -Path 'C:\Data\apres_migration.csv'

$ecarts = Compare-DataSet -Reference $avant -Difference $apres -KeyColumns 'ClientId'

# Synthese par type d'ecart
$ecarts | Group-Object Statut | Select-Object Name, Count | Format-Table -AutoSize

# Detail des seules modifications
$ecarts | Where-Object Statut -eq 'MODIFIE' | Format-Table -AutoSize

# Export du rapport complet
$ecarts | Export-CsvFast -Path 'C:\Data\ecarts_migration.csv'


# ##############################################################################
# RECETTE 5 : Detecter les doublons
# ##############################################################################

# Doublons dans les DONNEES (meme cle metier)
Import-CsvFast -Path 'C:\Data\clients.csv' |
    Find-DuplicateRow -KeyColumns 'CodeClient' |
    Format-Table -AutoSize

# Doublons sur cle composite
Import-CsvFast -Path 'C:\Data\mouvements.csv' |
    Find-DuplicateRow -KeyColumns 'CompteId', 'DateOperation', 'Montant'

# Doublons de FICHIERS (meme contenu, nom different)
Find-DuplicateFile -Path 'C:\Exports' -Recurse |
    Where-Object { -not $_.EstOriginal } |
    Format-Table Nom, TailleMo, Chemin -AutoSize


# ##############################################################################
# RECETTE 6 : Chaine ETL complete Excel -> controle -> SQL Server
# ##############################################################################

Start-LogSession -Path "$env:TEMP\etl_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$chrono = New-Timer

try {
    # --- EXTRACT ---
    Write-Log -Message 'Etape 1/4 : extraction Excel' -Level INFO
    $brut = Import-ExcelSheet -Path 'C:\Data\source.xlsx' -SheetName 'Donnees'
    Write-Log -Message ("{0} lignes extraites" -f @($brut).Count) -Level INFO
    Get-Timing -Timer $chrono -Label 'Extraction' -Reset

    # --- TRANSFORM ---
    Write-Log -Message 'Etape 2/4 : typage et transformation' -Level INFO
    $transforme = $brut |
        ConvertTo-TypedObject -Schema @{ Montant = 'decimal'; DateOp = 'datetime' } |
        Where-Object { $null -ne $_.Montant -and $_.Montant -gt 0 } |
        Select-Object *, @{ Name = 'DateChargement'; Expression = { Get-Date } }
    Get-Timing -Timer $chrono -Label 'Transformation' -Reset

    # --- CONTROLE QUALITE (bloquant) ---
    Write-Log -Message 'Etape 3/4 : controle qualite' -Level INFO
    $violations = $transforme | Test-DataQuality -Rules @{
        Montant = @{ Required = $true; MinValue = 0 }
    }
    if ($violations) {
        throw ("Controle qualite echoue : {0} violation(s)" -f @($violations).Count)
    }

    # --- LOAD ---
    Write-Log -Message 'Etape 4/4 : chargement SQL Server' -Level INFO
    if (-not (Test-SqlConnection -Server 'SRVSQL01' -Database 'DWH_PROD')) {
        throw 'Connexion SQL impossible'
    }
    $transforme | Import-ToSqlTable -Server 'SRVSQL01' -Database 'DWH_PROD' `
        -TableName 'dbo.Staging_Ventes' -TruncateFirst -Confirm:$false
    Get-Timing -Timer $chrono -Label 'Chargement' -Reset

    Write-Log -Message 'ETL termine avec succes' -Level SUCCESS
}
catch {
    Write-Log -Message ("ECHEC : {0}" -f $_.Exception.Message) -Level ERROR
    Write-Log -Message ("Ligne {0} : {1}" -f $_.InvocationInfo.ScriptLineNumber,
                        $_.InvocationInfo.Line.Trim()) -Level ERROR
    throw
}
finally {
    Stop-LogSession
}


# ##############################################################################
# RECETTE 7 : Interroger SQL Server sans SSMS
# ##############################################################################

# Requete simple
Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH_PROD' `
    -Query 'SELECT TOP 100 * FROM dbo.Clients' | Format-Table -AutoSize

# Requete parametree (protection contre l'injection SQL - A UTILISER SYSTEMATIQUEMENT)
$sql = @'
SELECT Region, COUNT(*) AS Nb, SUM(Montant) AS Total
FROM dbo.Ventes
WHERE DateVente >= @debut AND DateVente < @fin
GROUP BY Region
ORDER BY Total DESC
'@

Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH_PROD' -Query $sql -Parameters @{
    debut = [datetime]'2026-01-01'
    fin   = [datetime]'2026-07-01'
} | Format-Table -AutoSize

# Extraire une requete vers Excel
Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH_PROD' -Query $sql |
    Export-ExcelSheet -Path 'C:\Rapports\ventes.xlsx' -SheetName 'Synthese' -AutoFilter

# Connaitre la structure d'une table
Get-SqlTableSchema -Server 'SRVSQL01' -Database 'DWH_PROD' -TableName 'Ventes' |
    Format-Table -AutoSize

# Commande de modification : TOUJOURS tester avec -WhatIf d'abord
Invoke-SqlNonQuery -Server 'SRVSQL01' -Database 'DWH_PROD' `
    -Query 'DELETE FROM dbo.Staging WHERE DateChargement < @limite' `
    -Parameters @{ limite = (Get-Date).AddDays(-30) } `
    -WhatIf


# ##############################################################################
# RECETTE 8 : Rechercher dans des milliers de fichiers
# ##############################################################################

# Ou est utilisee cette table dans mes scripts SQL ?
Search-InFile -Path 'C:\Scripts\SQL' -Pattern 'KPA_PARTIES' -Filter '*.sql' -Recurse -SimpleMatch |
    Format-Table Fichier, Ligne, Texte -AutoSize

# Toutes les erreurs Oracle dans les logs du mois
Search-InFile -Path 'C:\Logs' -Pattern 'ORA-\d{5}' -Filter '*.log' -Recurse |
    Group-Object { $_.Texte -replace '.*(ORA-\d{5}).*', '$1' } |
    Sort-Object Count -Descending |
    Select-Object Name, Count

# Trouver les scripts contenant un mot de passe en clair (audit de securite)
Search-InFile -Path 'C:\Scripts' -Pattern '(password|pwd|mot_de_passe)\s*=' -Recurse |
    Format-Table Fichier, Ligne -AutoSize


# ##############################################################################
# RECETTE 9 : Manipuler de gros fichiers
# ##############################################################################

# Compter les lignes d'un fichier de 5 Go sans le charger en memoire
Measure-FileLine -Path 'C:\Data\enorme.csv'

# Le decouper pour qu'il passe dans Excel (limite : 1 048 576 lignes)
Split-LargeFile -Path 'C:\Data\enorme.csv' -LinesPerFile 500000 -HasHeader

# Consolider des exports quotidiens en un fichier mensuel
Merge-CsvFile -Path 'C:\Exports\Quotidien' -Filter '*.csv' `
    -Destination 'C:\Exports\consolide_202608.csv' -AddSourceColumn

# Corriger un encodage ANSI hérité en UTF-8
Convert-FileEncoding -Path 'C:\Data\legacy.csv' -To UTF8

# Suivre un log en temps reel (equivalent tail -f)
Get-FileTail -Path 'C:\Logs\traitement.log' -Count 20 -Wait


# ##############################################################################
# RECETTE 10 : Ranger et archiver automatiquement
# ##############################################################################

# Inventaire prealable : que contient ce dossier ?
Get-FileInventory -Path 'C:\Depot' -Recurse |
    Group-Object Extension |
    Select-Object Name, Count, @{ N = 'TotalMo'; E = { [math]::Round(($_.Group | Measure-Object TailleMo -Sum).Sum, 1) } } |
    Sort-Object TotalMo -Descending |
    Format-Table -AutoSize

# Classer par extension (TOUJOURS tester avec -WhatIf d'abord)
Move-FileByRule -Path 'C:\Depot' -Mode ByExtension -WhatIf
Move-FileByRule -Path 'C:\Depot' -Mode ByExtension

# Archiver par annee/mois
Move-FileByRule -Path 'C:\Depot' -Destination 'C:\Archives' -Mode ByDate

# Classer selon des regles metier
Move-FileByRule -Path 'C:\Depot' -Mode ByPattern -PatternRules @{
    '^FACT_'      = 'Factures'
    '^CMD_'       = 'Commandes'
    '^EXPORT_DWH' = 'Datawarehouse'
    '\.log$'      = 'Logs'
}

# Sauvegarder avant modification, en conservant 5 versions
Backup-File -Path 'C:\CRE\CRE.xlsx' -MaxBackups 5

# Purger les vieux logs (verifier avec -WhatIf avant !)
Remove-OldFile -Path 'C:\Logs' -DaysOld 90 -Filter '*.log' -WhatIf


# ##############################################################################
# RECETTE 11 : Excel - operations courantes
# ##############################################################################

# Quelles feuilles contient ce classeur ?
Get-ExcelSheetName -Path 'C:\CRE\CRE.xlsx' | Format-Table -AutoSize

# Importer une feuille et filtrer
Import-ExcelSheet -Path 'C:\CRE\CRE.xlsx' -SheetName 'CRE' |
    Where-Object { $_.TYPE_CRE -eq 'Differentiel' -and $_.CRE_STATUS -eq 'Valide' } |
    Select-Object CRE, TYPE_CRE, CRE_STATUS |
    Format-Table -AutoSize

# Convertir toutes les feuilles en CSV (les traitements deviennent bien plus rapides)
Convert-ExcelToCsv -Path 'C:\CRE\CRE.xlsx' -OutputFolder 'C:\CRE\csv'

# Ecrire un rapport dans un nouveau classeur
$resultats | Export-ExcelSheet -Path 'C:\Rapports\resultat.xlsx' `
    -SheetName 'Analyse' -AutoFilter -FreezeHeader

# Ajouter une feuille a un classeur existant (les autres feuilles sont preservees)
$autreJeu | Export-ExcelSheet -Path 'C:\Rapports\resultat.xlsx' -SheetName 'Detail'


# ##############################################################################
# RECETTE 12 : Jointure entre deux sources (technique de la hashtable)
# ##############################################################################
# 100 000 lignes x 10 000 references :
#   double boucle    = 1 milliard d'operations -> plusieurs heures
#   index hashtable  = 110 000 operations      -> quelques secondes

$referentiel = Import-CsvFast -Path 'C:\Data\referentiel_produits.csv'
$ventes      = Import-CsvFast -Path 'C:\Data\ventes.csv'

# Etape 1 : indexer le referentiel (une seule passe)
$index = @{}
foreach ($r in $referentiel) { $index[$r.CodeProduit] = $r }

# Etape 2 : enrichir les ventes (une seule passe, acces instantane)
$enrichi = foreach ($v in $ventes) {
    $ref = $index[$v.CodeProduit]
    [PSCustomObject]@{
        CodeProduit = $v.CodeProduit
        Quantite    = $v.Quantite
        Montant     = $v.Montant
        # Valeurs issues du referentiel, avec repli si non trouve
        Libelle     = if ($ref) { $ref.Libelle } else { 'INCONNU' }
        Famille     = if ($ref) { $ref.Famille } else { 'NON CLASSE' }
        Trouve      = ($null -ne $ref)
    }
}

# Controle : combien de codes n'ont pas de correspondance ?
$enrichi | Where-Object { -not $_.Trouve } |
    Select-Object CodeProduit -Unique |
    Format-Table -AutoSize


# ##############################################################################
# RECETTE 13 : Agregations facon SQL
# ##############################################################################

$data = Import-CsvFast -Path 'C:\Data\ventes.csv' |
        ConvertTo-TypedObject -Schema @{ Montant = 'decimal'; Quantite = 'int' }

# SELECT Region, COUNT(*), SUM(Montant), AVG(Montant) FROM ... GROUP BY Region
$data | Group-Object Region | ForEach-Object {
    $stats = $_.Group | Measure-Object Montant -Sum -Average -Maximum -Minimum
    [PSCustomObject]@{
        Region   = $_.Name
        Nb       = $_.Count
        Total    = [math]::Round($stats.Sum, 2)
        Moyenne  = [math]::Round($stats.Average, 2)
        Maximum  = $stats.Maximum
        Minimum  = $stats.Minimum
    }
} | Sort-Object Total -Descending | Format-Table -AutoSize

# TOP N par groupe (equivalent ROW_NUMBER() OVER PARTITION BY)
$data | Group-Object Region | ForEach-Object {
    $_.Group | Sort-Object Montant -Descending | Select-Object -First 3
}

# Tableau croise (pivot) Region x Mois
$data | Group-Object Region | ForEach-Object {
    $ligne = [ordered]@{ Region = $_.Name }
    foreach ($mois in 1..12) {
        $somme = ($_.Group | Where-Object { $_.DateVente.Month -eq $mois } |
                  Measure-Object Montant -Sum).Sum
        $ligne["M$mois"] = if ($somme) { [math]::Round($somme, 0) } else { 0 }
    }
    [PSCustomObject]$ligne
} | Format-Table -AutoSize


# ##############################################################################
# RECETTE 14 : Script ETL industrialise (modele a reutiliser)
# ##############################################################################
<#
Enregistrez ce modele comme base de tous vos nouveaux scripts.
Il integre : parametres valides, journalisation, gestion d'erreur,
mesure de temps, et diagnostic exploitable a distance.

--------------------------------------------------------------------------------
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$Server,

    [Parameter(Mandatory = $true)]
    [string]$Database,

    [string]$LogFolder = "$env:TEMP\etl_logs"
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\PSToolkit.psm1" -Force

$horodatage = Get-Date -Format 'yyyyMMdd_HHmmss'
Start-LogSession -Path (Join-Path $LogFolder "etl_$horodatage.log")
$chrono = New-Timer

try {
    Write-Log -Message ("Demarrage - source : {0}" -f $SourcePath) -Level INFO

    # 1. Verifications prealables (echouer vite plutot que tard)
    if (-not (Test-SqlConnection -Server $Server -Database $Database)) {
        throw 'Connexion SQL indisponible'
    }

    # 2. Sauvegarde de securite
    Backup-File -Path $SourcePath -MaxBackups 10 | Out-Null

    # 3. Extraction
    $donnees = Import-CsvFast -Path $SourcePath
    Write-Log -Message ("{0} lignes lues" -f @($donnees).Count) -Level INFO

    # 4. Controle qualite bloquant
    $violations = $donnees | Test-DataQuality -Rules $regles -MaxViolations 100
    if ($violations) {
        $violations | Export-CsvFast -Path (Join-Path $LogFolder "violations_$horodatage.csv")
        throw ("Qualite insuffisante : {0} violation(s)" -f @($violations).Count)
    }

    # 5. Chargement
    $donnees | Import-ToSqlTable -Server $Server -Database $Database `
        -TableName 'dbo.Staging' -TruncateFirst -Confirm:$false

    Get-Timing -Timer $chrono -Label 'Duree totale'
    Write-Log -Message 'Traitement termine avec succes' -Level SUCCESS
    exit 0
}
catch {
    Write-Log -Message ("ECHEC : {0}" -f $_.Exception.Message) -Level ERROR
    Write-Log -Message ("Ligne {0} : {1}" -f $_.InvocationInfo.ScriptLineNumber,
                        $_.InvocationInfo.Line.Trim()) -Level ERROR
    Write-Log -Message $_.ScriptStackTrace -Level ERROR
    exit 1        # code de sortie non nul : detectable par un ordonnanceur
}
finally {
    Stop-LogSession
}
--------------------------------------------------------------------------------
#>


# ##############################################################################
# RECETTE 15 : Mesurer et optimiser
# ##############################################################################

# Comparer deux approches : la difference est spectaculaire
$a = Measure-Command {
    $r = @()
    foreach ($i in 1..20000) { $r += $i }             # tableau + operateur +=
}
$b = Measure-Command {
    $r = New-Object 'System.Collections.Generic.List[int]'
    foreach ($i in 1..20000) { $r.Add($i) }           # List[T]
}
"Tableau += : {0:N0} ms" -f $a.TotalMilliseconds
"List<T>    : {0:N0} ms" -f $b.TotalMilliseconds
"Rapport    : x{0:N0}"   -f ($a.TotalMilliseconds / [Math]::Max($b.TotalMilliseconds, 1))

# Instrumenter un traitement par etapes
$t = New-Timer
$data = Import-CsvFast -Path 'C:\Data\gros.csv'
Get-Timing -Timer $t -Label 'Import' -Reset

$filtre = $data | Where-Object { $_.Statut -eq 'Valide' }
Get-Timing -Timer $t -Label 'Filtrage' -Reset

$filtre | Export-CsvFast -Path 'C:\Data\sortie.csv'
Get-Timing -Timer $t -Label 'Export'
