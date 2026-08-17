<#
================================================================================
 PSToolkit.psm1 - Boite a outils d'automatisation ETL / Datawarehouse
================================================================================

 AUTEUR      : Bibliotheque generique
 COMPATIBLE  : Windows PowerShell 5.1 et PowerShell 7+
 PREREQUIS   : AUCUN droit administrateur, AUCUN module externe.
               Excel n'est requis que pour les fonctions Excel-*.

 PHILOSOPHIE :
   - Syntaxe simple et explicite (pas de constructions fragiles selon la version)
   - Performance : List[T], HashSet, StringBuilder, StreamReader, lecture COM en bloc
   - Securite : parametres SQL, -WhatIf sur les operations destructrices, -LiteralPath
   - Fiabilite : validation des entrees, liberation des ressources en finally

 CHARGEMENT :
   Import-Module C:\CRE\PSToolkit.psm1 -Force
   Get-Command -Module PSToolkit
   Get-Help Import-CsvFast -Full

================================================================================
 SOMMAIRE
================================================================================
 1. JOURNALISATION      Write-Log, Start-LogSession, Stop-LogSession
 2. ENCODAGE            Get-FileEncoding, Convert-FileEncoding, Read-TextFile,
                        Write-TextFile
 3. FICHIERS TEXTE      Measure-FileLine, Search-InFile, Split-LargeFile,
                        Get-FileHead, Get-FileTail
 4. CSV                 Get-CsvDelimiter, Import-CsvFast, ConvertTo-TypedObject,
                        Merge-CsvFile, Export-CsvFast
 5. QUALITE DE DONNEES  Get-DataProfile, Find-DuplicateRow, Compare-DataSet,
                        Test-DataQuality
 6. EXCEL (COM)         New-ExcelApp, Close-ExcelApp, Get-ExcelSheetName,
                        Import-ExcelSheet, Export-ExcelSheet, Convert-ExcelToCsv
 7. SQL SERVER          Test-SqlConnection, Invoke-SqlQuery, Invoke-SqlNonQuery,
                        Import-ToSqlTable, Get-SqlTableSchema
 8. FICHIERS / TRI      Get-FileInventory, Find-DuplicateFile, Move-FileByRule,
                        Backup-File, Remove-OldFile
 9. UTILITAIRES         New-Timer, Get-Timing, Test-IsNumeric, ConvertTo-SafeName
================================================================================
#>

# NOTE : Set-StrictMode n'est volontairement PAS active.
# En mode strict, l'acces a une propriete absente leve une exception, ce qui rend
# le traitement de donnees heterogenes (colonnes manquantes dans un CSV) fragile.
# Les fonctions verifient explicitement l'existence des proprietes a la place.

# Chargement de l'assembly SqlClient.
# Present nativement en PowerShell 5.1 ; en PowerShell 7 le chargement peut etre requis.
try {
    Add-Type -AssemblyName 'System.Data' -ErrorAction SilentlyContinue
}
catch {
    # Sans importance : les fonctions SQL signaleront le probleme si l'assembly manque
}

# Variables de module (prefixe $script: = visible dans tout le module uniquement)
$script:LogPath      = $null
$script:LogToConsole = $true


# ##############################################################################
# 1. JOURNALISATION
# ##############################################################################

function Start-LogSession {
    <#
    .SYNOPSIS
        Ouvre une session de journalisation vers un fichier.
    .DESCRIPTION
        Toutes les fonctions Write-Log suivantes ecriront dans ce fichier.
        Le fichier est cree s'il n'existe pas. Aucun droit admin necessaire
        tant que le dossier est accessible en ecriture (profil utilisateur, TEMP...).
    .PARAMETER Path
        Chemin du fichier de log. Si le dossier n'existe pas, il est cree.
    .PARAMETER NoConsole
        Desactive l'affichage console (le log n'ira que dans le fichier).
    .EXAMPLE
        Start-LogSession -Path "$env:TEMP\etl_$(Get-Date -Format 'yyyyMMdd').log"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$NoConsole
    )

    $dossier = Split-Path -Path $Path -Parent
    if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
        New-Item -Path $dossier -ItemType Directory -Force | Out-Null
    }

    $script:LogPath      = $Path
    $script:LogToConsole = -not $NoConsole

    Write-Log -Message ("=== Session demarree ({0}) ===" -f $env:USERNAME) -Level INFO
}


function Stop-LogSession {
    <#
    .SYNOPSIS
        Ferme la session de journalisation en cours.
    #>
    [CmdletBinding()]
    param()

    if ($script:LogPath) {
        Write-Log -Message "=== Session terminee ===" -Level INFO
        $script:LogPath = $null
    }
}


function Write-Log {
    <#
    .SYNOPSIS
        Ecrit un message horodate dans le log et/ou la console.
    .DESCRIPTION
        Chaque ligne est prefixee par la date et le niveau de gravite.
        Format : 2026-08-13 14:32:01 [INFO ] Message
    .PARAMETER Message
        Texte a journaliser.
    .PARAMETER Level
        Gravite : DEBUG, INFO, WARN, ERROR, SUCCESS.
    .EXAMPLE
        Write-Log -Message "Import termine : 1250 lignes" -Level SUCCESS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $horodatage = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $ligne = "{0} [{1,-7}] {2}" -f $horodatage, $Level, $Message

    # Ecriture fichier (append). Encodage UTF8 explicite pour les accents.
    if ($script:LogPath) {
        try {
            Add-Content -LiteralPath $script:LogPath -Value $ligne -Encoding UTF8
        }
        catch {
            # Ne jamais faire echouer le traitement principal a cause du log
            Write-Warning ("Ecriture log impossible : {0}" -f $_.Exception.Message)
        }
    }

    # Affichage console colore
    if ($script:LogToConsole) {
        $couleur = switch ($Level) {
            'DEBUG'   { 'DarkGray' }
            'INFO'    { 'White' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            default   { 'White' }
        }
        Write-Host $ligne -ForegroundColor $couleur
    }
}


# ##############################################################################
# 2. ENCODAGE
# ##############################################################################

function Get-FileEncoding {
    <#
    .SYNOPSIS
        Detecte l'encodage d'un fichier texte via son BOM.
    .DESCRIPTION
        Lit les premiers octets pour identifier la signature (BOM).
        Sans BOM, tente de distinguer UTF-8 valide d'un encodage ANSI.
        Utile avant tout import : un mauvais encodage corrompt les accents.
    .PARAMETER Path
        Chemin du fichier a analyser.
    .OUTPUTS
        Chaine : UTF8-BOM, UTF16-LE, UTF16-BE, UTF32-LE, UTF8-NoBOM, ANSI
    .EXAMPLE
        Get-FileEncoding -Path .\export.csv
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $flux = [System.IO.File]::OpenRead($Path)
    try {
        $tete = New-Object byte[] 4
        $lus = $flux.Read($tete, 0, 4)
    }
    finally {
        $flux.Dispose()
    }

    if ($lus -ge 3 -and $tete[0] -eq 0xEF -and $tete[1] -eq 0xBB -and $tete[2] -eq 0xBF) {
        return 'UTF8-BOM'
    }
    if ($lus -ge 4 -and $tete[0] -eq 0xFF -and $tete[1] -eq 0xFE -and $tete[2] -eq 0x00 -and $tete[3] -eq 0x00) {
        return 'UTF32-LE'
    }
    if ($lus -ge 2 -and $tete[0] -eq 0xFF -and $tete[1] -eq 0xFE) { return 'UTF16-LE' }
    if ($lus -ge 2 -and $tete[0] -eq 0xFE -and $tete[1] -eq 0xFF) { return 'UTF16-BE' }

    # Pas de BOM : on teste si le contenu est de l'UTF-8 valide.
    # UTF8Encoding avec throwOnInvalidBytes = true leve une exception si ce n'en est pas.
    try {
        $octets = [System.IO.File]::ReadAllBytes($Path)
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$strict.GetString($octets)
        return 'UTF8-NoBOM'
    }
    catch {
        return 'ANSI'
    }
}


function Read-TextFile {
    <#
    .SYNOPSIS
        Lit un fichier texte en gerant correctement le BOM et l'encodage.
    .DESCRIPTION
        Remplacement fiable de Get-Content -Raw.
        [System.IO.File]::ReadAllText detecte et retire le BOM automatiquement,
        ce qui evite l'erreur classique "Primitive JSON non valide" ou les
        caracteres parasites en debut de fichier.
    .PARAMETER Path
        Chemin du fichier.
    .PARAMETER Encoding
        UTF8 (defaut), ANSI, UTF16, ou Auto pour detection automatique.
    .EXAMPLE
        $json = Read-TextFile -Path .\config.json | ConvertFrom-Json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateSet('UTF8', 'ANSI', 'UTF16', 'Auto')]
        [string]$Encoding = 'Auto'
    )

    $enc = switch ($Encoding) {
        'UTF8'  { [System.Text.Encoding]::UTF8 }
        'ANSI'  { [System.Text.Encoding]::Default }
        'UTF16' { [System.Text.Encoding]::Unicode }
        'Auto'  {
            # ReadAllText avec detection automatique du BOM
            $detecte = Get-FileEncoding -Path $Path
            if ($detecte -eq 'ANSI') { [System.Text.Encoding]::Default }
            else { $null }   # $null = laisser .NET detecter via le BOM
        }
    }

    if ($null -eq $enc) {
        return [System.IO.File]::ReadAllText($Path)
    }
    return [System.IO.File]::ReadAllText($Path, $enc)
}


function Write-TextFile {
    <#
    .SYNOPSIS
        Ecrit un fichier texte avec un controle precis du BOM.
    .DESCRIPTION
        En PowerShell 5.1, Set-Content -Encoding UTF8 ajoute TOUJOURS un BOM,
        ce qui casse les imports SQL Server / Unix / certains parseurs.
        Cette fonction permet d'ecrire de l'UTF-8 SANS BOM.
    .PARAMETER Path
        Chemin du fichier de sortie.
    .PARAMETER Content
        Contenu a ecrire (chaine ou tableau de chaines).
    .PARAMETER Encoding
        UTF8 (sans BOM par defaut), UTF8BOM, ANSI, UTF16.
    .PARAMETER Append
        Ajoute a la fin au lieu d'ecraser.
    .EXAMPLE
        Write-TextFile -Path .\sortie.csv -Content $lignes -Encoding UTF8
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [string[]]$Content,

        [ValidateSet('UTF8', 'UTF8BOM', 'ANSI', 'UTF16')]
        [string]$Encoding = 'UTF8',

        [switch]$Append
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Ecrire le fichier')) { return }

    $enc = switch ($Encoding) {
        'UTF8'    { New-Object System.Text.UTF8Encoding($false) }   # $false = SANS BOM
        'UTF8BOM' { New-Object System.Text.UTF8Encoding($true) }
        'ANSI'    { [System.Text.Encoding]::Default }
        'UTF16'   { [System.Text.Encoding]::Unicode }
    }

    $dossier = Split-Path -Path $Path -Parent
    if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
        New-Item -Path $dossier -ItemType Directory -Force | Out-Null
    }

    $texte = $Content -join [Environment]::NewLine

    if ($Append -and (Test-Path -LiteralPath $Path)) {
        $existant = [System.IO.File]::ReadAllText($Path)
        $texte = $existant + [Environment]::NewLine + $texte
    }

    [System.IO.File]::WriteAllText($Path, $texte, $enc)
}


function Convert-FileEncoding {
    <#
    .SYNOPSIS
        Convertit un fichier d'un encodage vers un autre.
    .DESCRIPTION
        Cas typique : un export ANSI d'un vieux systeme doit etre injecte
        en UTF-8 dans le datawarehouse.
    .PARAMETER Path
        Fichier source.
    .PARAMETER Destination
        Fichier de sortie. Si omis, ecrase la source (une sauvegarde .bak est creee).
    .PARAMETER To
        Encodage cible : UTF8 (sans BOM), UTF8BOM, ANSI, UTF16.
    .EXAMPLE
        Convert-FileEncoding -Path .\legacy.csv -To UTF8
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [string]$Destination,

        [ValidateSet('UTF8', 'UTF8BOM', 'ANSI', 'UTF16')]
        [string]$To = 'UTF8'
    )

    $contenu = Read-TextFile -Path $Path -Encoding Auto

    if (-not $Destination) {
        $Destination = $Path
        $sauvegarde = "{0}.bak_{1}" -f $Path, (Get-Date -Format 'yyyyMMdd_HHmmss')
        if ($PSCmdlet.ShouldProcess($sauvegarde, 'Creer une sauvegarde')) {
            Copy-Item -LiteralPath $Path -Destination $sauvegarde
            Write-Log -Message ("Sauvegarde creee : {0}" -f $sauvegarde) -Level INFO
        }
    }

    Write-TextFile -Path $Destination -Content $contenu -Encoding $To
    Write-Log -Message ("Converti en {0} : {1}" -f $To, $Destination) -Level SUCCESS
}


# ##############################################################################
# 3. FICHIERS TEXTE
# ##############################################################################

function Measure-FileLine {
    <#
    .SYNOPSIS
        Compte les lignes d'un fichier, meme tres volumineux.
    .DESCRIPTION
        Utilise un StreamReader : la memoire reste constante quelle que soit
        la taille du fichier (teste sur plusieurs Go).
        (Get-Content $f).Count chargerait tout en RAM et saturerait la machine.
    .PARAMETER Path
        Chemin du fichier.
    .EXAMPLE
        Measure-FileLine -Path .\gros_export.csv
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    process {
        $compteur = 0
        $lecteur = New-Object System.IO.StreamReader($Path)
        try {
            while ($null -ne $lecteur.ReadLine()) { $compteur++ }
        }
        finally {
            $lecteur.Dispose()
        }

        [PSCustomObject]@{
            Fichier    = Split-Path -Path $Path -Leaf
            Chemin     = $Path
            Lignes     = $compteur
            TailleMo   = [math]::Round((Get-Item -LiteralPath $Path).Length / 1MB, 2)
        }
    }
}


function Search-InFile {
    <#
    .SYNOPSIS
        Recherche un motif dans un ou plusieurs fichiers (equivalent grep).
    .DESCRIPTION
        Parcourt les fichiers en flux (memoire constante) avec une regex
        compilee une seule fois. Beaucoup plus rapide que Select-String
        sur de gros volumes.
    .PARAMETER Path
        Dossier ou fichier a analyser.
    .PARAMETER Pattern
        Motif recherche (texte simple ou expression reguliere).
    .PARAMETER Filter
        Filtre de nom de fichier (ex : *.log). Applique a la source = rapide.
    .PARAMETER Recurse
        Descend dans les sous-dossiers.
    .PARAMETER SimpleMatch
        Traite le motif comme du texte litteral, pas comme une regex.
    .PARAMETER CaseSensitive
        Respecte la casse.
    .PARAMETER MaxResults
        Arrete la recherche apres N resultats (0 = illimite).
    .EXAMPLE
        Search-InFile -Path C:\Logs -Pattern 'ORA-\d+' -Filter *.log -Recurse
    .EXAMPLE
        Search-InFile -Path C:\SQL -Pattern 'KPA_PARTIES' -Filter *.sql -SimpleMatch
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [string]$Filter = '*',

        [switch]$Recurse,
        [switch]$SimpleMatch,
        [switch]$CaseSensitive,

        [int]$MaxResults = 0
    )

    # Construction des options regex : syntaxe chaine (fiable toutes versions)
    $options = if ($CaseSensitive) {
        [System.Text.RegularExpressions.RegexOptions]'Compiled'
    } else {
        [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled'
    }

    $motif = if ($SimpleMatch) { [regex]::Escape($Pattern) } else { $Pattern }
    $rx = New-Object System.Text.RegularExpressions.Regex($motif, $options)

    # Liste des fichiers a traiter
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fichiers = @(Get-Item -LiteralPath $Path)
    }
    else {
        $params = @{ Path = $Path; Filter = $Filter; File = $true }
        if ($Recurse) { $params['Recurse'] = $true }
        $fichiers = Get-ChildItem @params -ErrorAction SilentlyContinue
    }

    $total = 0

    foreach ($f in $fichiers) {
        $numLigne = 0
        $lecteur = $null
        try {
            $lecteur = New-Object System.IO.StreamReader($f.FullName)
            while ($null -ne ($ligne = $lecteur.ReadLine())) {
                $numLigne++
                if ($rx.IsMatch($ligne)) {
                    [PSCustomObject]@{
                        Fichier = $f.Name
                        Ligne   = $numLigne
                        Texte   = $ligne.Trim()
                        Chemin  = $f.FullName
                    }
                    $total++
                    if ($MaxResults -gt 0 -and $total -ge $MaxResults) { return }
                }
            }
        }
        catch {
            Write-Warning ("Lecture impossible : {0} ({1})" -f $f.FullName, $_.Exception.Message)
        }
        finally {
            if ($lecteur) { $lecteur.Dispose() }
        }
    }
}


function Split-LargeFile {
    <#
    .SYNOPSIS
        Decoupe un gros fichier en plusieurs fichiers plus petits.
    .DESCRIPTION
        Indispensable quand un export depasse les limites d'un outil
        (Excel : 1 048 576 lignes) ou pour paralleliser un chargement.
        L'en-tete peut etre repete dans chaque morceau.
    .PARAMETER Path
        Fichier source.
    .PARAMETER LinesPerFile
        Nombre de lignes de donnees par fichier de sortie.
    .PARAMETER OutputFolder
        Dossier de destination (defaut : meme dossier que la source).
    .PARAMETER HasHeader
        Le fichier a une ligne d'en-tete a repeter dans chaque morceau.
    .EXAMPLE
        Split-LargeFile -Path .\export.csv -LinesPerFile 500000 -HasHeader
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 100000000)]
        [int]$LinesPerFile,

        [string]$OutputFolder,

        [switch]$HasHeader
    )

    $source = Get-Item -LiteralPath $Path
    if (-not $OutputFolder) { $OutputFolder = $source.DirectoryName }
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $baseNom  = [System.IO.Path]::GetFileNameWithoutExtension($source.Name)
    $ext      = $source.Extension
    $encodage = New-Object System.Text.UTF8Encoding($false)

    $lecteur  = New-Object System.IO.StreamReader($source.FullName)
    $ecrivain = $null
    $entete   = $null
    $numMorceau = 0
    $lignesEcrites = 0
    $fichiersCrees = New-Object 'System.Collections.Generic.List[string]'

    try {
        if ($HasHeader) { $entete = $lecteur.ReadLine() }

        while ($null -ne ($ligne = $lecteur.ReadLine())) {

            # Ouvrir un nouveau morceau si necessaire
            if ($null -eq $ecrivain -or $lignesEcrites -ge $LinesPerFile) {
                if ($ecrivain) { $ecrivain.Dispose(); $ecrivain = $null }

                $numMorceau++
                $nomSortie = "{0}_partie{1:D3}{2}" -f $baseNom, $numMorceau, $ext
                $cheminSortie = Join-Path -Path $OutputFolder -ChildPath $nomSortie

                if ($PSCmdlet.ShouldProcess($cheminSortie, 'Creer le fichier')) {
                    $ecrivain = New-Object System.IO.StreamWriter($cheminSortie, $false, $encodage)
                    if ($entete) { $ecrivain.WriteLine($entete) }
                    $fichiersCrees.Add($cheminSortie)
                }
                $lignesEcrites = 0
            }

            if ($ecrivain) {
                $ecrivain.WriteLine($ligne)
                $lignesEcrites++
            }
        }
    }
    finally {
        if ($ecrivain) { $ecrivain.Dispose() }
        $lecteur.Dispose()
    }

    Write-Log -Message ("Decoupage termine : {0} fichier(s) cree(s)" -f $fichiersCrees.Count) -Level SUCCESS
    return $fichiersCrees
}


function Get-FileHead {
    <#
    .SYNOPSIS
        Affiche les N premieres lignes d'un fichier sans le charger entierement.
    .DESCRIPTION
        Equivalent de la commande Unix 'head'. Permet d'inspecter la structure
        d'un fichier de 10 Go instantanement.
    .PARAMETER Path
        Chemin du fichier.
    .PARAMETER Count
        Nombre de lignes a afficher (defaut 10).
    .EXAMPLE
        Get-FileHead -Path .\enorme.csv -Count 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateRange(1, 10000)]
        [int]$Count = 10
    )

    $lecteur = New-Object System.IO.StreamReader($Path)
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $ligne = $lecteur.ReadLine()
            if ($null -eq $ligne) { break }
            Write-Output $ligne
        }
    }
    finally {
        $lecteur.Dispose()
    }
}


function Get-FileTail {
    <#
    .SYNOPSIS
        Affiche les N dernieres lignes d'un fichier.
    .DESCRIPTION
        Utile pour verifier la fin d'un export ou lire la fin d'un log.
        Utilise Get-Content -Tail qui est optimise (lecture depuis la fin).
    .PARAMETER Path
        Chemin du fichier.
    .PARAMETER Count
        Nombre de lignes (defaut 10).
    .PARAMETER Wait
        Suit le fichier en temps reel (equivalent 'tail -f').
    .EXAMPLE
        Get-FileTail -Path .\traitement.log -Count 20 -Wait
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateRange(1, 10000)]
        [int]$Count = 10,

        [switch]$Wait
    )

    if ($Wait) {
        Get-Content -LiteralPath $Path -Tail $Count -Wait
    }
    else {
        Get-Content -LiteralPath $Path -Tail $Count
    }
}


# ##############################################################################
# 4. CSV
# ##############################################################################

function Get-CsvDelimiter {
    <#
    .SYNOPSIS
        Detecte automatiquement le separateur d'un fichier CSV.
    .DESCRIPTION
        Analyse les premieres lignes et retient le caractere dont le nombre
        d'occurrences est le plus eleve ET le plus regulier d'une ligne a l'autre.
        Evite d'avoir a ouvrir le fichier pour verifier a chaque fois.
    .PARAMETER Path
        Chemin du fichier CSV.
    .PARAMETER SampleLines
        Nombre de lignes analysees (defaut 5).
    .EXAMPLE
        $sep = Get-CsvDelimiter -Path .\export.csv
        Import-Csv .\export.csv -Delimiter $sep
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [ValidateRange(2, 100)]
        [int]$SampleLines = 5
    )

    $candidats = @(';', ',', "`t", '|')
    $lignes = New-Object 'System.Collections.Generic.List[string]'

    $lecteur = New-Object System.IO.StreamReader($Path)
    try {
        for ($i = 0; $i -lt $SampleLines; $i++) {
            $l = $lecteur.ReadLine()
            if ($null -eq $l) { break }
            if (-not [string]::IsNullOrWhiteSpace($l)) { $lignes.Add($l) }
        }
    }
    finally {
        $lecteur.Dispose()
    }

    if ($lignes.Count -eq 0) {
        Write-Warning "Fichier vide : separateur ';' par defaut"
        return ';'
    }

    $meilleur = ';'
    $meilleurScore = -1

    foreach ($sep in $candidats) {
        $comptes = New-Object 'System.Collections.Generic.List[int]'
        foreach ($l in $lignes) {
            # Compte les occurrences du separateur dans la ligne
            $n = ($l.ToCharArray() | Where-Object { $_ -eq $sep }).Count
            $comptes.Add($n)
        }

        $moyenne = ($comptes | Measure-Object -Average).Average
        if ($moyenne -lt 1) { continue }   # separateur absent

        # Regularite : toutes les lignes doivent avoir le meme nombre de separateurs
        $regulier = ($comptes | Select-Object -Unique).Count -eq 1
        $score = if ($regulier) { $moyenne * 10 } else { $moyenne }

        if ($score -gt $meilleurScore) {
            $meilleurScore = $score
            $meilleur = $sep
        }
    }

    return $meilleur
}


function Import-CsvFast {
    <#
    .SYNOPSIS
        Import CSV robuste avec detection du separateur et de l'encodage.
    .DESCRIPTION
        Enveloppe Import-Csv en ajoutant :
          - detection automatique du separateur (si non precise)
          - detection de l'encodage
          - controle du nombre de lignes lues
          - journalisation
        Pour de tres gros fichiers (> 500 Mo), preferer Import-CsvStream.
    .PARAMETER Path
        Chemin du fichier CSV.
    .PARAMETER Delimiter
        Separateur. Si omis, detection automatique.
    .PARAMETER Encoding
        Encodage. Si omis, detection automatique.
    .PARAMETER First
        Ne charge que les N premieres lignes (utile pour inspecter un gros fichier).
    .EXAMPLE
        $data = Import-CsvFast -Path .\clients.csv
    .EXAMPLE
        $apercu = Import-CsvFast -Path .\gros.csv -First 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [string]$Delimiter,

        [ValidateSet('UTF8', 'ANSI', 'UTF16', 'Auto')]
        [string]$Encoding = 'Auto',

        [int]$First = 0
    )

    if (-not $Delimiter) {
        $Delimiter = Get-CsvDelimiter -Path $Path
        $affichage = if ($Delimiter -eq "`t") { 'TAB' } else { $Delimiter }
        Write-Verbose ("Separateur detecte : {0}" -f $affichage)
    }

    # Traduction de l'encodage pour Import-Csv
    $encPs = switch ($Encoding) {
        'UTF8'  { 'UTF8' }
        'ANSI'  { 'Default' }
        'UTF16' { 'Unicode' }
        'Auto'  {
            $d = Get-FileEncoding -Path $Path
            if ($d -eq 'ANSI') { 'Default' } else { 'UTF8' }
        }
    }

    if ($First -gt 0) {
        # Lecture partielle : on ne charge que l'en-tete + N lignes
        $lignes = Get-FileHead -Path $Path -Count ($First + 1)
        return $lignes | ConvertFrom-Csv -Delimiter $Delimiter
    }

    return Import-Csv -LiteralPath $Path -Delimiter $Delimiter -Encoding $encPs
}


function ConvertTo-TypedObject {
    <#
    .SYNOPSIS
        Convertit les colonnes texte d'un import CSV en types reels.
    .DESCRIPTION
        Import-Csv renvoie TOUT en chaine de caracteres : "100" + 5 donne "1005".
        Cette fonction applique un schema de typage pour obtenir de vrais
        nombres, dates et booleens, indispensables aux calculs et aux
        chargements SQL.
    .PARAMETER InputObject
        Objets issus d'Import-Csv (accepte le pipeline).
    .PARAMETER Schema
        Hashtable colonne -> type : @{ Montant = 'decimal'; DateOp = 'datetime' }
        Types supportes : int, long, decimal, double, datetime, bool, string
    .PARAMETER DateFormat
        Format attendu pour les dates (defaut : detection automatique).
    .PARAMETER Culture
        Culture pour l'analyse des nombres (defaut fr-FR : virgule decimale).
    .EXAMPLE
        Import-Csv .\ventes.csv |
            ConvertTo-TypedObject -Schema @{ Montant='decimal'; DateVente='datetime' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [hashtable]$Schema,

        [string]$DateFormat,

        [string]$Culture = 'fr-FR'
    )

    begin {
        $ci = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
        $nbStyle = [System.Globalization.NumberStyles]::Any
        $dtStyle = [System.Globalization.DateTimeStyles]::None
    }

    process {
        foreach ($obj in $InputObject) {

            $nouveau = [ordered]@{}

            foreach ($prop in $obj.PSObject.Properties) {
                $nom    = $prop.Name
                $valeur = $prop.Value

                if (-not $Schema.ContainsKey($nom)) {
                    $nouveau[$nom] = $valeur          # colonne non typee : inchangee
                    continue
                }

                $type = $Schema[$nom]

                # Valeur vide -> $null (et non 0 ou 01/01/0001)
                if ($null -eq $valeur -or [string]::IsNullOrWhiteSpace([string]$valeur)) {
                    $nouveau[$nom] = $null
                    continue
                }

                $txt = ([string]$valeur).Trim()

                switch ($type) {
                    'int' {
                        $r = 0
                        if ([int]::TryParse($txt, [ref]$r)) { $nouveau[$nom] = $r }
                        else { $nouveau[$nom] = $null; Write-Verbose "int invalide : $nom = $txt" }
                    }
                    'long' {
                        $r = [long]0
                        if ([long]::TryParse($txt, [ref]$r)) { $nouveau[$nom] = $r }
                        else { $nouveau[$nom] = $null; Write-Verbose "long invalide : $nom = $txt" }
                    }
                    'decimal' {
                        # On accepte indifferemment la virgule et le point decimal
                        $normalise = $txt -replace '\s', ''
                        $r = [decimal]0
                        if ([decimal]::TryParse($normalise, $nbStyle, $ci, [ref]$r)) {
                            $nouveau[$nom] = $r
                        }
                        elseif ([decimal]::TryParse(($normalise -replace ',', '.'), $nbStyle,
                                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$r)) {
                            $nouveau[$nom] = $r
                        }
                        else { $nouveau[$nom] = $null; Write-Verbose "decimal invalide : $nom = $txt" }
                    }
                    'double' {
                        $r = [double]0
                        if ([double]::TryParse($txt, $nbStyle, $ci, [ref]$r)) { $nouveau[$nom] = $r }
                        else { $nouveau[$nom] = $null }
                    }
                    'datetime' {
                        $r = [datetime]::MinValue
                        $ok = $false
                        if ($DateFormat) {
                            $ok = [datetime]::TryParseExact($txt, $DateFormat, $ci, $dtStyle, [ref]$r)
                        }
                        if (-not $ok) { $ok = [datetime]::TryParse($txt, $ci, $dtStyle, [ref]$r) }
                        if ($ok) { $nouveau[$nom] = $r }
                        else { $nouveau[$nom] = $null; Write-Verbose "date invalide : $nom = $txt" }
                    }
                    'bool' {
                        $vrais = @('1', 'true', 'vrai', 'oui', 'o', 'y', 'yes', 'x')
                        $nouveau[$nom] = $vrais -contains $txt.ToLowerInvariant()
                    }
                    default {
                        $nouveau[$nom] = $txt
                    }
                }
            }

            [PSCustomObject]$nouveau
        }
    }
}


function Export-CsvFast {
    <#
    .SYNOPSIS
        Export CSV avec controle du BOM et du separateur.
    .DESCRIPTION
        Export-Csv en PowerShell 5.1 ecrit un BOM UTF-8 qui fait echouer
        de nombreux imports (SQL Server BULK INSERT, outils Unix).
        Cette fonction produit un fichier propre, sans BOM par defaut.
    .PARAMETER InputObject
        Objets a exporter.
    .PARAMETER Path
        Fichier de sortie.
    .PARAMETER Delimiter
        Separateur (defaut ';').
    .PARAMETER WithBom
        Force l'ecriture du BOM (necessaire pour ouvrir directement dans Excel
        avec des accents).
    .EXAMPLE
        $data | Export-CsvFast -Path .\sortie.csv
    .EXAMPLE
        $data | Export-CsvFast -Path .\pour_excel.csv -WithBom
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string]$Delimiter = ';',

        [switch]$WithBom
    )

    begin {
        $tampon = New-Object 'System.Collections.Generic.List[PSObject]'
    }

    process {
        foreach ($o in $InputObject) { $tampon.Add($o) }
    }

    end {
        if ($tampon.Count -eq 0) {
            Write-Warning "Aucune donnee a exporter"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Path, 'Exporter en CSV')) { return }

        $lignes = $tampon | ConvertTo-Csv -NoTypeInformation -Delimiter $Delimiter
        $encodage = if ($WithBom) { 'UTF8BOM' } else { 'UTF8' }

        Write-TextFile -Path $Path -Content $lignes -Encoding $encodage
        Write-Log -Message ("Export CSV : {0} lignes -> {1}" -f $tampon.Count, $Path) -Level SUCCESS
    }
}


function Merge-CsvFile {
    <#
    .SYNOPSIS
        Fusionne plusieurs fichiers CSV de meme structure en un seul.
    .DESCRIPTION
        Cas typique : consolider des exports quotidiens en un fichier mensuel.
        Traitement en flux : fonctionne meme avec des centaines de fichiers
        volumineux sans saturer la memoire.
        Une colonne indiquant le fichier d'origine peut etre ajoutee.
    .PARAMETER Path
        Dossier contenant les fichiers, ou tableau de chemins.
    .PARAMETER Filter
        Filtre de nom (defaut *.csv).
    .PARAMETER Destination
        Fichier de sortie.
    .PARAMETER AddSourceColumn
        Ajoute une colonne 'FichierSource' avec le nom du fichier d'origine.
    .EXAMPLE
        Merge-CsvFile -Path C:\Exports\Jour -Destination C:\Exports\mois.csv -AddSourceColumn
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Path,

        [string]$Filter = '*.csv',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [switch]$AddSourceColumn
    )

    # Resolution de la liste de fichiers
    $fichiers = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $p -Filter $Filter -File) { $fichiers.Add($f) }
        }
        elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $fichiers.Add((Get-Item -LiteralPath $p))
        }
    }

    if ($fichiers.Count -eq 0) {
        Write-Warning "Aucun fichier trouve"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, ("Fusionner {0} fichiers" -f $fichiers.Count))) {
        return
    }

    $encodage = New-Object System.Text.UTF8Encoding($false)
    $ecrivain = New-Object System.IO.StreamWriter($Destination, $false, $encodage)
    $enteteEcrit = $false
    $totalLignes = 0

    try {
        foreach ($f in $fichiers) {
            $lecteur = New-Object System.IO.StreamReader($f.FullName)
            try {
                $entete = $lecteur.ReadLine()
                if ($null -eq $entete) { continue }

                if (-not $enteteEcrit) {
                    if ($AddSourceColumn) {
                        $ecrivain.WriteLine(("{0};FichierSource" -f $entete))
                    }
                    else {
                        $ecrivain.WriteLine($entete)
                    }
                    $enteteEcrit = $true
                }

                while ($null -ne ($ligne = $lecteur.ReadLine())) {
                    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }
                    if ($AddSourceColumn) {
                        $ecrivain.WriteLine(("{0};{1}" -f $ligne, $f.Name))
                    }
                    else {
                        $ecrivain.WriteLine($ligne)
                    }
                    $totalLignes++
                }
            }
            finally {
                $lecteur.Dispose()
            }
            Write-Verbose ("Fusionne : {0}" -f $f.Name)
        }
    }
    finally {
        $ecrivain.Dispose()
    }

    Write-Log -Message ("Fusion : {0} fichiers, {1} lignes -> {2}" -f $fichiers.Count, $totalLignes, $Destination) -Level SUCCESS
}


# ##############################################################################
# 5. QUALITE DE DONNEES
# ##############################################################################

function Get-DataProfile {
    <#
    .SYNOPSIS
        Profile un jeu de donnees : statistiques par colonne.
    .DESCRIPTION
        Reproduit ce qu'un outil de data profiling ferait :
        pour chaque colonne, le taux de remplissage, le nombre de valeurs
        distinctes, les valeurs min/max et un echantillon.
        Premiere chose a faire quand on decouvre un fichier inconnu.
    .PARAMETER InputObject
        Donnees a analyser (issues d'Import-Csv, d'Excel ou de SQL).
    .PARAMETER SampleValues
        Nombre de valeurs d'exemple a afficher (defaut 3).
    .EXAMPLE
        Import-Csv .\inconnu.csv | Get-DataProfile | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [ValidateRange(0, 20)]
        [int]$SampleValues = 3
    )

    begin {
        $donnees = New-Object 'System.Collections.Generic.List[PSObject]'
    }

    process {
        foreach ($o in $InputObject) { $donnees.Add($o) }
    }

    end {
        if ($donnees.Count -eq 0) {
            Write-Warning "Aucune donnee"
            return
        }

        $total = $donnees.Count
        $colonnes = $donnees[0].PSObject.Properties.Name

        foreach ($col in $colonnes) {

            $distinctes = New-Object 'System.Collections.Generic.HashSet[string]'
            $exemples   = New-Object 'System.Collections.Generic.List[string]'
            $vides      = 0
            $numeriques = 0
            $longMin    = [int]::MaxValue
            $longMax    = 0

            foreach ($ligne in $donnees) {
                $v = $ligne.$col

                if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) {
                    $vides++
                    continue
                }

                $txt = ([string]$v).Trim()
                [void]$distinctes.Add($txt)

                if ($txt.Length -lt $longMin) { $longMin = $txt.Length }
                if ($txt.Length -gt $longMax) { $longMax = $txt.Length }

                $tmp = [decimal]0
                if ([decimal]::TryParse($txt, [ref]$tmp)) { $numeriques++ }

                if ($exemples.Count -lt $SampleValues -and -not $exemples.Contains($txt)) {
                    $exemples.Add($txt)
                }
            }

            $remplies = $total - $vides
            $typeProbable = if ($remplies -eq 0) { 'VIDE' }
                            elseif ($numeriques -eq $remplies) { 'NUMERIQUE' }
                            elseif ($distinctes.Count -le 10) { 'CATEGORIE' }
                            else { 'TEXTE' }

            [PSCustomObject]@{
                Colonne        = $col
                Total          = $total
                Remplies       = $remplies
                Vides          = $vides
                TauxRemplissage = "{0:N1}%" -f (100 * $remplies / $total)
                Distinctes     = $distinctes.Count
                TypeProbable   = $typeProbable
                LongueurMin    = if ($longMin -eq [int]::MaxValue) { 0 } else { $longMin }
                LongueurMax    = $longMax
                Exemples       = ($exemples -join ' | ')
            }
        }
    }
}


function Find-DuplicateRow {
    <#
    .SYNOPSIS
        Detecte les doublons dans un jeu de donnees selon une ou plusieurs cles.
    .DESCRIPTION
        Utilise une hashtable : performance lineaire meme sur des centaines
        de milliers de lignes (une double boucle serait quadratique).
    .PARAMETER InputObject
        Donnees a analyser.
    .PARAMETER KeyColumns
        Colonne(s) formant la cle d'unicite.
    .PARAMETER ShowAll
        Renvoie toutes les occurrences (defaut : uniquement un resume par cle).
    .EXAMPLE
        Import-Csv .\clients.csv | Find-DuplicateRow -KeyColumns 'CodeClient'
    .EXAMPLE
        $data | Find-DuplicateRow -KeyColumns 'Code','Date' -ShowAll
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KeyColumns,

        [switch]$ShowAll
    )

    begin {
        # cle -> liste des lignes portant cette cle
        $index = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[PSObject]]'
        $numLigne = 0
    }

    process {
        foreach ($o in $InputObject) {
            $numLigne++

            # Construction de la cle composite
            $parties = New-Object 'System.Collections.Generic.List[string]'
            foreach ($c in $KeyColumns) {
                $v = if ($o.PSObject.Properties.Name -contains $c) { [string]$o.$c } else { '' }
                $parties.Add($v.Trim().ToUpperInvariant())
            }
            $cle = $parties -join '||'

            if (-not $index.ContainsKey($cle)) {
                $index[$cle] = New-Object 'System.Collections.Generic.List[PSObject]'
            }

            # On memorise la ligne avec son numero d'origine
            $marque = $o | Select-Object *
            $marque | Add-Member -NotePropertyName '_NumLigne' -NotePropertyValue $numLigne -Force
            $index[$cle].Add($marque)
        }
    }

    end {
        foreach ($cle in $index.Keys) {
            $groupe = $index[$cle]
            if ($groupe.Count -le 1) { continue }      # pas un doublon

            if ($ShowAll) {
                foreach ($l in $groupe) { Write-Output $l }
            }
            else {
                [PSCustomObject]@{
                    Cle          = $cle -replace '\|\|', ' | '
                    Occurrences  = $groupe.Count
                    NumerosLigne = (($groupe | ForEach-Object { $_._NumLigne }) -join ', ')
                }
            }
        }
    }
}


function Compare-DataSet {
    <#
    .SYNOPSIS
        Compare deux jeux de donnees et identifie ajouts, suppressions et modifications.
    .DESCRIPTION
        Equivalent d'un MERGE SQL en memoire. Indispensable pour :
          - controler une migration (avant / apres)
          - detecter les ecarts entre source et cible
          - construire un delta pour un chargement incrementiel
        Complexite lineaire grace a l'indexation par hashtable.
    .PARAMETER Reference
        Jeu de donnees de reference (l'ancien / la source).
    .PARAMETER Difference
        Jeu de donnees compare (le nouveau / la cible).
    .PARAMETER KeyColumns
        Colonne(s) identifiant une ligne de maniere unique.
    .PARAMETER CompareColumns
        Colonnes a comparer pour detecter une modification.
        Si omis, toutes les colonnes communes sont comparees.
    .EXAMPLE
        $avant = Import-Csv .\avant.csv
        $apres = Import-Csv .\apres.csv
        Compare-DataSet -Reference $avant -Difference $apres -KeyColumns 'ID'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Reference,

        [Parameter(Mandatory = $true)]
        [PSObject[]]$Difference,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KeyColumns,

        [string[]]$CompareColumns
    )

    # Fonction interne de construction de cle
    function New-Cle {
        param($Objet, [string[]]$Colonnes)
        $parties = New-Object 'System.Collections.Generic.List[string]'
        foreach ($c in $Colonnes) {
            $v = if ($Objet.PSObject.Properties.Name -contains $c) { [string]$Objet.$c } else { '' }
            $parties.Add($v.Trim().ToUpperInvariant())
        }
        return ($parties -join '||')
    }

    # Determination des colonnes a comparer
    if (-not $CompareColumns) {
        $colsRef = $Reference[0].PSObject.Properties.Name
        $colsDif = $Difference[0].PSObject.Properties.Name
        $CompareColumns = $colsRef | Where-Object { $colsDif -contains $_ -and $KeyColumns -notcontains $_ }
    }

    # Indexation du jeu de reference : O(n)
    $indexRef = New-Object 'System.Collections.Generic.Dictionary[string,PSObject]'
    foreach ($r in $Reference) {
        $indexRef[(New-Cle -Objet $r -Colonnes $KeyColumns)] = $r
    }

    $clesVues = New-Object 'System.Collections.Generic.HashSet[string]'

    # Parcours du jeu compare : O(m)
    foreach ($d in $Difference) {
        $cle = New-Cle -Objet $d -Colonnes $KeyColumns
        [void]$clesVues.Add($cle)

        if (-not $indexRef.ContainsKey($cle)) {
            [PSCustomObject]@{
                Statut        = 'AJOUTE'
                Cle           = $cle -replace '\|\|', ' | '
                Colonne       = ''
                ValeurAvant   = ''
                ValeurApres   = ''
            }
            continue
        }

        # La cle existe des deux cotes : comparer les colonnes
        $r = $indexRef[$cle]
        foreach ($c in $CompareColumns) {
            $va = if ($r.PSObject.Properties.Name -contains $c) { [string]$r.$c } else { '' }
            $vb = if ($d.PSObject.Properties.Name -contains $c) { [string]$d.$c } else { '' }

            if ($va.Trim() -ne $vb.Trim()) {
                [PSCustomObject]@{
                    Statut      = 'MODIFIE'
                    Cle         = $cle -replace '\|\|', ' | '
                    Colonne     = $c
                    ValeurAvant = $va
                    ValeurApres = $vb
                }
            }
        }
    }

    # Cles presentes dans la reference mais absentes du jeu compare
    foreach ($cle in $indexRef.Keys) {
        if (-not $clesVues.Contains($cle)) {
            [PSCustomObject]@{
                Statut      = 'SUPPRIME'
                Cle         = $cle -replace '\|\|', ' | '
                Colonne     = ''
                ValeurAvant = ''
                ValeurApres = ''
            }
        }
    }
}


function Test-DataQuality {
    <#
    .SYNOPSIS
        Controle un jeu de donnees selon un ensemble de regles.
    .DESCRIPTION
        Verifie les regles courantes de qualite avant chargement en DWH :
        obligatoire, unicite, format, longueur, plage de valeurs, liste fermee.
        Renvoie la liste des violations trouvees.
    .PARAMETER InputObject
        Donnees a controler.
    .PARAMETER Rules
        Hashtable de regles par colonne. Cles supportees :
          Required  = $true              colonne obligatoire (non vide)
          Unique    = $true              valeurs uniques
          Pattern   = '^\d{5}$'          conformite regex
          MaxLength = 50                 longueur maximale
          MinValue  = 0                  valeur numerique minimale
          MaxValue  = 100                valeur numerique maximale
          AllowedValues = @('A','B')     liste fermee
    .PARAMETER MaxViolations
        Arrete apres N violations (0 = illimite).
    .EXAMPLE
        $regles = @{
            CodeClient = @{ Required = $true; Unique = $true; Pattern = '^CLI\d{4}$' }
            Montant    = @{ Required = $true; MinValue = 0 }
            Statut     = @{ AllowedValues = @('Valide','Invalide') }
        }
        Import-Csv .\data.csv | Test-DataQuality -Rules $regles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [hashtable]$Rules,

        [int]$MaxViolations = 0
    )

    begin {
        $numLigne = 0
        $nbViolations = 0
        # Suivi des valeurs deja vues, par colonne soumise a unicite
        $valeursVues = @{}
        foreach ($col in $Rules.Keys) {
            if ($Rules[$col].ContainsKey('Unique') -and $Rules[$col]['Unique']) {
                $valeursVues[$col] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
        }
        # Cache des regex compilees
        $regexCache = @{}
    }

    process {
        foreach ($obj in $InputObject) {
            $numLigne++

            foreach ($col in $Rules.Keys) {

                if ($MaxViolations -gt 0 -and $nbViolations -ge $MaxViolations) { return }

                $regle = $Rules[$col]
                $existe = $obj.PSObject.Properties.Name -contains $col

                if (-not $existe) {
                    [PSCustomObject]@{
                        Ligne = $numLigne; Colonne = $col; Regle = 'ColonneAbsente'
                        Valeur = ''; Message = 'La colonne n''existe pas dans les donnees'
                    }
                    $nbViolations++
                    continue
                }

                $valeur = $obj.$col
                $txt = if ($null -eq $valeur) { '' } else { ([string]$valeur).Trim() }
                $estVide = [string]::IsNullOrWhiteSpace($txt)

                # --- Required ---
                if ($regle.ContainsKey('Required') -and $regle['Required'] -and $estVide) {
                    [PSCustomObject]@{
                        Ligne = $numLigne; Colonne = $col; Regle = 'Required'
                        Valeur = $txt; Message = 'Valeur obligatoire manquante'
                    }
                    $nbViolations++
                    continue      # inutile de tester le reste sur une valeur vide
                }

                if ($estVide) { continue }

                # --- Unique ---
                if ($regle.ContainsKey('Unique') -and $regle['Unique']) {
                    $cle = $txt.ToUpperInvariant()
                    if (-not $valeursVues[$col].Add($cle)) {
                        [PSCustomObject]@{
                            Ligne = $numLigne; Colonne = $col; Regle = 'Unique'
                            Valeur = $txt; Message = 'Valeur en doublon'
                        }
                        $nbViolations++
                    }
                }

                # --- Pattern ---
                if ($regle.ContainsKey('Pattern')) {
                    $motif = $regle['Pattern']
                    if (-not $regexCache.ContainsKey($motif)) {
                        $regexCache[$motif] = New-Object System.Text.RegularExpressions.Regex(
                            $motif, [System.Text.RegularExpressions.RegexOptions]'Compiled')
                    }
                    if (-not $regexCache[$motif].IsMatch($txt)) {
                        [PSCustomObject]@{
                            Ligne = $numLigne; Colonne = $col; Regle = 'Pattern'
                            Valeur = $txt; Message = ("Ne respecte pas le format {0}" -f $motif)
                        }
                        $nbViolations++
                    }
                }

                # --- MaxLength ---
                if ($regle.ContainsKey('MaxLength') -and $txt.Length -gt $regle['MaxLength']) {
                    [PSCustomObject]@{
                        Ligne = $numLigne; Colonne = $col; Regle = 'MaxLength'
                        Valeur = $txt
                        Message = ("Longueur {0} > maximum {1}" -f $txt.Length, $regle['MaxLength'])
                    }
                    $nbViolations++
                }

                # --- MinValue / MaxValue ---
                if ($regle.ContainsKey('MinValue') -or $regle.ContainsKey('MaxValue')) {
                    $num = [decimal]0
                    if ([decimal]::TryParse(($txt -replace ',', '.'),
                            [System.Globalization.NumberStyles]::Any,
                            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {

                        if ($regle.ContainsKey('MinValue') -and $num -lt $regle['MinValue']) {
                            [PSCustomObject]@{
                                Ligne = $numLigne; Colonne = $col; Regle = 'MinValue'
                                Valeur = $txt
                                Message = ("Valeur {0} < minimum {1}" -f $num, $regle['MinValue'])
                            }
                            $nbViolations++
                        }
                        if ($regle.ContainsKey('MaxValue') -and $num -gt $regle['MaxValue']) {
                            [PSCustomObject]@{
                                Ligne = $numLigne; Colonne = $col; Regle = 'MaxValue'
                                Valeur = $txt
                                Message = ("Valeur {0} > maximum {1}" -f $num, $regle['MaxValue'])
                            }
                            $nbViolations++
                        }
                    }
                    else {
                        [PSCustomObject]@{
                            Ligne = $numLigne; Colonne = $col; Regle = 'Numerique'
                            Valeur = $txt; Message = 'Valeur non numerique'
                        }
                        $nbViolations++
                    }
                }

                # --- AllowedValues ---
                if ($regle.ContainsKey('AllowedValues')) {
                    $autorisees = $regle['AllowedValues']
                    $trouve = $false
                    foreach ($a in $autorisees) {
                        if ($txt -eq [string]$a) { $trouve = $true; break }
                    }
                    if (-not $trouve) {
                        [PSCustomObject]@{
                            Ligne = $numLigne; Colonne = $col; Regle = 'AllowedValues'
                            Valeur = $txt
                            Message = ("Valeur non autorisee (attendu : {0})" -f ($autorisees -join ', '))
                        }
                        $nbViolations++
                    }
                }
            }
        }
    }
}


# ##############################################################################
# 6. EXCEL (via COM - necessite Excel installe, mais AUCUN droit admin)
# ##############################################################################

function New-ExcelApp {
    <#
    .SYNOPSIS
        Cree une instance Excel invisible et optimisee pour l'automatisation.
    .DESCRIPTION
        Desactive l'affichage, les alertes et les evenements : les traitements
        sont alors 5 a 10 fois plus rapides.
        IMPORTANT : toujours appeler Close-ExcelApp dans un bloc finally,
        sinon un processus EXCEL.EXE reste en memoire indefiniment.
    .EXAMPLE
        $xl = New-ExcelApp
        try { ... } finally { Close-ExcelApp -Excel $xl }
    #>
    [CmdletBinding()]
    param()

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible        = $false
    $excel.DisplayAlerts  = $false
    $excel.ScreenUpdating = $false
    $excel.EnableEvents   = $false
    return $excel
}


function Close-ExcelApp {
    <#
    .SYNOPSIS
        Ferme proprement une instance Excel et libere la memoire COM.
    .DESCRIPTION
        Le simple fait de perdre la reference PowerShell ne ferme PAS Excel :
        il faut explicitement Quit() puis ReleaseComObject().
        Sans cela, les processus EXCEL.EXE s'accumulent jusqu'a saturer le poste.
    .PARAMETER Excel
        L'instance Excel a fermer.
    .PARAMETER Workbook
        Le classeur a fermer (optionnel).
    .PARAMETER Save
        Sauvegarde le classeur avant fermeture.
    .EXAMPLE
        Close-ExcelApp -Excel $xl -Workbook $wb -Save
    #>
    [CmdletBinding()]
    param(
        $Excel,
        $Workbook,
        [switch]$Save
    )

    if ($Workbook) {
        try {
            if ($Save) { $Workbook.Save() }
            $Workbook.Close($false) | Out-Null
        }
        catch {
            Write-Warning ("Fermeture classeur : {0}" -f $_.Exception.Message)
        }
    }

    if ($Excel) {
        try {
            $Excel.ScreenUpdating = $true
            $Excel.EnableEvents   = $true
            $Excel.Quit()
        }
        catch {
            Write-Warning ("Fermeture Excel : {0}" -f $_.Exception.Message)
        }
    }

    # Liberation explicite des references COM
    foreach ($o in @($Workbook, $Excel)) {
        if ($o) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { }
        }
    }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}


function Get-ExcelSheetName {
    <#
    .SYNOPSIS
        Liste les feuilles d'un classeur Excel.
    .DESCRIPTION
        Permet de decouvrir la structure d'un classeur sans l'ouvrir a la main.
    .PARAMETER Path
        Chemin du classeur.
    .EXAMPLE
        Get-ExcelSheetName -Path C:\CRE\CRE.xlsx
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $chemin = (Resolve-Path -LiteralPath $Path).Path
    $excel = $null
    $wb = $null

    try {
        $excel = New-ExcelApp
        # ReadOnly = $true : n'altere jamais le fichier source
        $wb = $excel.Workbooks.Open($chemin, 0, $true)

        $index = 0
        foreach ($ws in $wb.Worksheets) {
            $index++
            [PSCustomObject]@{
                Index        = $index
                Nom          = $ws.Name
                LignesUtiles = $ws.UsedRange.Rows.Count
                ColonnesUtiles = $ws.UsedRange.Columns.Count
                Visible      = ($ws.Visible -eq -1)
            }
        }
    }
    finally {
        Close-ExcelApp -Excel $excel -Workbook $wb
    }
}


function Import-ExcelSheet {
    <#
    .SYNOPSIS
        Importe une feuille Excel sous forme d'objets PowerShell.
    .DESCRIPTION
        Lit toute la plage utilisee EN UN SEUL appel COM (UsedRange.Value2),
        ce qui est environ 100 fois plus rapide qu'une lecture cellule par cellule.
        La premiere ligne sert d'en-tete (noms de colonnes).

        Note technique : le tableau renvoye par Excel est 1-based et son acces
        se fait via .GetValue(ligne, colonne) - la syntaxe $tab[$l,$c] est
        ambigue selon les versions de PowerShell et doit etre evitee.
    .PARAMETER Path
        Chemin du classeur.
    .PARAMETER SheetName
        Nom de la feuille. Si omis, la premiere feuille est utilisee.
    .PARAMETER HeaderRow
        Numero de la ligne d'en-tete (defaut 1).
    .PARAMETER MaxRows
        Limite le nombre de lignes lues (0 = toutes).
    .EXAMPLE
        $data = Import-ExcelSheet -Path C:\CRE\CRE.xlsx -SheetName 'CRE'
    .EXAMPLE
        Import-ExcelSheet -Path .\donnees.xlsx | Where-Object { $_.Statut -eq 'Valide' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [string]$SheetName,

        [ValidateRange(1, 1000)]
        [int]$HeaderRow = 1,

        [int]$MaxRows = 0
    )

    $chemin = (Resolve-Path -LiteralPath $Path).Path
    $excel = $null
    $wb = $null

    try {
        $excel = New-ExcelApp
        $wb = $excel.Workbooks.Open($chemin, 0, $true)     # ouverture en lecture seule

        # Selection de la feuille
        $ws = $null
        if ($SheetName) {
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $SheetName) { $ws = $s; break }
            }
            if ($null -eq $ws) {
                throw ("Feuille introuvable : {0}" -f $SheetName)
            }
        }
        else {
            $ws = $wb.Worksheets.Item(1)
        }

        # LECTURE EN BLOC : un seul aller-retour COM
        $data = $ws.UsedRange.Value2

        if ($data -isnot [System.Array]) {
            Write-Warning "Feuille vide ou contenant une seule cellule"
            return
        }

        $rMin = [int]$data.GetLowerBound(0)
        $rMax = [int]$data.GetUpperBound(0)
        $cMin = [int]$data.GetLowerBound(1)
        $cMax = [int]$data.GetUpperBound(1)

        # Ligne d'en-tete : construction de la liste des noms de colonnes
        $ligneEntete = $rMin + $HeaderRow - 1
        $entetes = New-Object 'System.Collections.Generic.List[string]'

        for ($c = $cMin; $c -le $cMax; $c++) {
            $v = $data.GetValue($ligneEntete, $c)
            $nom = if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) {
                "Colonne{0}" -f $c
            } else {
                ([string]$v).Trim()
            }

            # Gestion des doublons de noms de colonnes
            $nomFinal = $nom
            $suffixe = 1
            while ($entetes.Contains($nomFinal)) {
                $suffixe++
                $nomFinal = "{0}_{1}" -f $nom, $suffixe
            }
            $entetes.Add($nomFinal)
        }

        # Lignes de donnees
        $compteur = 0
        for ($r = $ligneEntete + 1; $r -le $rMax; $r++) {

            if ($MaxRows -gt 0 -and $compteur -ge $MaxRows) { break }

            $ligne = [ordered]@{}
            $ligneVide = $true

            for ($c = $cMin; $c -le $cMax; $c++) {
                $v = $data.GetValue($r, $c)
                $nomCol = $entetes[$c - $cMin]

                if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                    $ligneVide = $false
                }
                $ligne[$nomCol] = $v
            }

            if (-not $ligneVide) {
                [PSCustomObject]$ligne
                $compteur++
            }
        }
    }
    finally {
        Close-ExcelApp -Excel $excel -Workbook $wb
    }
}


function Export-ExcelSheet {
    <#
    .SYNOPSIS
        Ecrit des objets PowerShell dans une feuille Excel.
    .DESCRIPTION
        Cree ou remplace une feuille dans un classeur existant ou nouveau.

        Deux modes d'ecriture :
          - CellByCell (defaut) : le plus fiable, recommande jusqu'a ~20 000 cellules.
          - Bulk : ecriture par blocs, plus rapide, mais certaines versions d'Excel
            renvoient une OutOfMemoryException trompeuse lors du marshaling COM.

        Pour de tres gros volumes, exporter en CSV (Export-CsvFast) est plus sur
        ET plus rapide que de passer par Excel.
    .PARAMETER InputObject
        Donnees a ecrire.
    .PARAMETER Path
        Classeur de destination (cree s'il n'existe pas).
    .PARAMETER SheetName
        Nom de la feuille (remplacee si elle existe deja).
    .PARAMETER Mode
        CellByCell (defaut) ou Bulk.
    .PARAMETER AutoFilter
        Ajoute un filtre automatique sur la ligne d'en-tete.
    .PARAMETER FreezeHeader
        Fige la ligne d'en-tete.
    .EXAMPLE
        $data | Export-ExcelSheet -Path .\rapport.xlsx -SheetName 'Resultats' -AutoFilter
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string]$SheetName = 'Donnees',

        [ValidateSet('CellByCell', 'Bulk')]
        [string]$Mode = 'CellByCell',

        [switch]$AutoFilter,
        [switch]$FreezeHeader
    )

    begin {
        $tampon = New-Object 'System.Collections.Generic.List[PSObject]'
    }

    process {
        foreach ($o in $InputObject) { $tampon.Add($o) }
    }

    end {
        if ($tampon.Count -eq 0) {
            Write-Warning "Aucune donnee a exporter"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Path, ("Ecrire {0} lignes" -f $tampon.Count))) {
            return
        }

        $colonnes = $tampon[0].PSObject.Properties.Name
        $nbLignes = $tampon.Count
        $nbCols   = $colonnes.Count

        $excel = $null
        $wb = $null

        try {
            $excel = New-ExcelApp

            # Ouverture ou creation du classeur
            $existe = Test-Path -LiteralPath $Path
            if ($existe) {
                $cheminComplet = (Resolve-Path -LiteralPath $Path).Path
                $wb = $excel.Workbooks.Open($cheminComplet, 0, $false)
            }
            else {
                $wb = $excel.Workbooks.Add()
                $cheminComplet = $Path
            }

            # Suppression de la feuille homonyme si elle existe
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $SheetName) { $s.Delete(); break }
            }

            $ws = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
            $ws.Name = $SheetName

            if ($Mode -eq 'Bulk') {
                # --- Ecriture par bloc ---
                $arr = [System.Array]::CreateInstance([object], ($nbLignes + 1), $nbCols)

                for ($c = 0; $c -lt $nbCols; $c++) {
                    $arr.SetValue($colonnes[$c], 0, $c)
                }
                for ($r = 0; $r -lt $nbLignes; $r++) {
                    for ($c = 0; $c -lt $nbCols; $c++) {
                        $arr.SetValue($tampon[$r].($colonnes[$c]), ($r + 1), $c)
                    }
                }

                $plage = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item($nbLignes + 1, $nbCols))
                $plage.Value2 = $arr
            }
            else {
                # --- Ecriture cellule par cellule (la plus fiable) ---
                for ($c = 0; $c -lt $nbCols; $c++) {
                    $ws.Cells.Item(1, $c + 1).Value2 = $colonnes[$c]
                }
                for ($r = 0; $r -lt $nbLignes; $r++) {
                    $ligneExcel = $r + 2      # +1 en-tete, +1 index 1-based Excel
                    for ($c = 0; $c -lt $nbCols; $c++) {
                        $ws.Cells.Item($ligneExcel, $c + 1).Value2 = $tampon[$r].($colonnes[$c])
                    }
                }
            }

            # Mise en forme de l'en-tete
            $entete = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $nbCols))
            $entete.Font.Bold = $true
            $entete.Interior.Color = 65535        # jaune

            if ($AutoFilter) {
                try { $entete.AutoFilter() | Out-Null } catch { }
            }
            if ($FreezeHeader) {
                try {
                    $ws.Activate()
                    $ws.Application.ActiveWindow.SplitRow = 1
                    $ws.Application.ActiveWindow.FreezePanes = $true
                }
                catch { }
            }

            try { $ws.Columns.AutoFit() | Out-Null } catch { }

            # Sauvegarde
            if ($existe) {
                $wb.Save()
            }
            else {
                # 51 = format xlsx
                $wb.SaveAs($cheminComplet, 51)
            }

            Write-Log -Message ("Export Excel : {0} lignes -> {1} [{2}]" -f $nbLignes, $Path, $SheetName) -Level SUCCESS
        }
        finally {
            Close-ExcelApp -Excel $excel -Workbook $wb
        }
    }
}


function Convert-ExcelToCsv {
    <#
    .SYNOPSIS
        Convertit une ou toutes les feuilles d'un classeur Excel en fichiers CSV.
    .DESCRIPTION
        Tres utile pour industrialiser : une fois en CSV, les traitements sont
        beaucoup plus rapides et ne necessitent plus Excel.
    .PARAMETER Path
        Classeur source.
    .PARAMETER OutputFolder
        Dossier de destination (defaut : celui du classeur).
    .PARAMETER SheetName
        Feuille a convertir. Si omis, toutes les feuilles sont converties.
    .PARAMETER Delimiter
        Separateur du CSV (defaut ';').
    .EXAMPLE
        Convert-ExcelToCsv -Path C:\CRE\CRE.xlsx -SheetName 'CRE'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [string]$OutputFolder,

        [string]$SheetName,

        [string]$Delimiter = ';'
    )

    $source = Get-Item -LiteralPath $Path
    if (-not $OutputFolder) { $OutputFolder = $source.DirectoryName }
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $baseNom = [System.IO.Path]::GetFileNameWithoutExtension($source.Name)

    # Determination des feuilles a traiter
    $feuilles = if ($SheetName) {
        @($SheetName)
    } else {
        (Get-ExcelSheetName -Path $Path | Where-Object { $_.Visible }).Nom
    }

    $crees = New-Object 'System.Collections.Generic.List[string]'

    foreach ($f in $feuilles) {
        Write-Log -Message ("Conversion de la feuille : {0}" -f $f) -Level INFO

        $data = Import-ExcelSheet -Path $Path -SheetName $f
        if (-not $data) {
            Write-Warning ("Feuille vide, ignoree : {0}" -f $f)
            continue
        }

        $nomSortie = ConvertTo-SafeName -Name ("{0}_{1}.csv" -f $baseNom, $f)
        $cheminSortie = Join-Path -Path $OutputFolder -ChildPath $nomSortie

        $data | Export-CsvFast -Path $cheminSortie -Delimiter $Delimiter
        $crees.Add($cheminSortie)
    }

    return $crees
}


# ##############################################################################
# 7. SQL SERVER (via .NET natif - AUCUN module ni droit admin requis)
# ##############################################################################

function Get-SqlConnectionString {
    <#
    .SYNOPSIS
        Construit une chaine de connexion SQL Server.
    .DESCRIPTION
        Par defaut, utilise l'authentification Windows integree :
        aucun mot de passe n'est stocke ni transmis. C'est la methode
        la plus sure et celle qui fonctionne sans droits particuliers.
    .PARAMETER Server
        Nom ou adresse de l'instance SQL Server.
    .PARAMETER Database
        Nom de la base.
    .PARAMETER Credential
        Identifiants SQL (uniquement si l'authentification Windows est impossible).
    .PARAMETER TimeoutSeconds
        Delai de connexion (defaut 15 s).
    .EXAMPLE
        Get-SqlConnectionString -Server 'SRVSQL01' -Database 'DWH_PROD'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,

        [System.Management.Automation.PSCredential]$Credential,

        [int]$TimeoutSeconds = 15
    )

    if ($Credential) {
        $utilisateur = $Credential.UserName
        $motDePasse  = $Credential.GetNetworkCredential().Password
        return ("Server={0};Database={1};User Id={2};Password={3};Connect Timeout={4};" -f
                $Server, $Database, $utilisateur, $motDePasse, $TimeoutSeconds)
    }

    # Authentification Windows integree : recommandee
    return ("Server={0};Database={1};Integrated Security=True;Connect Timeout={2};" -f
            $Server, $Database, $TimeoutSeconds)
}


function Test-SqlConnection {
    <#
    .SYNOPSIS
        Verifie qu'une connexion SQL Server fonctionne.
    .DESCRIPTION
        A appeler en debut de traitement : mieux vaut echouer immediatement
        avec un message clair qu'apres 20 minutes de preparation de donnees.
    .PARAMETER Server
        Instance SQL Server.
    .PARAMETER Database
        Base de donnees.
    .PARAMETER Credential
        Identifiants SQL (optionnel).
    .EXAMPLE
        if (-not (Test-SqlConnection -Server 'SRVSQL01' -Database 'DWH')) { return }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [System.Management.Automation.PSCredential]$Credential
    )

    $cs = Get-SqlConnectionString -Server $Server -Database $Database -Credential $Credential -TimeoutSeconds 10
    $conn = New-Object System.Data.SqlClient.SqlConnection($cs)

    try {
        $conn.Open()
        Write-Log -Message ("Connexion OK : {0}\{1}" -f $Server, $Database) -Level SUCCESS
        return $true
    }
    catch {
        Write-Log -Message ("Connexion ECHOUEE : {0}" -f $_.Exception.Message) -Level ERROR
        return $false
    }
    finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}


function Invoke-SqlQuery {
    <#
    .SYNOPSIS
        Execute une requete SELECT et renvoie les resultats en objets PowerShell.
    .DESCRIPTION
        N'utilise que System.Data.SqlClient, present nativement dans .NET Framework :
        aucun module SqlServer a installer, aucun droit administrateur.

        SECURITE : utilisez TOUJOURS le parametre -Parameters plutot que de
        concatener des valeurs dans la requete. Cela protege contre l'injection SQL
        et gere correctement les apostrophes (ex : un nom comme O'Brien).
    .PARAMETER Server
        Instance SQL Server.
    .PARAMETER Database
        Base de donnees.
    .PARAMETER Query
        Requete SQL a executer.
    .PARAMETER Parameters
        Hashtable des parametres : @{ region = 'IDF'; annee = 2026 }
        Referencez-les dans la requete par @region, @annee.
    .PARAMETER TimeoutSeconds
        Delai d'execution (defaut 300 s pour les requetes DWH lourdes).
    .PARAMETER AsDataTable
        Renvoie un DataTable brut (utile pour SqlBulkCopy) au lieu d'objets.
    .PARAMETER Credential
        Identifiants SQL (optionnel).
    .EXAMPLE
        Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH' -Query 'SELECT TOP 10 * FROM dbo.Clients'
    .EXAMPLE
        $sql = 'SELECT * FROM dbo.Ventes WHERE Region = @reg AND Annee = @an'
        Invoke-SqlQuery -Server 'SRV' -Database 'DWH' -Query $sql -Parameters @{ reg='IDF'; an=2026 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [hashtable]$Parameters = @{},

        [int]$TimeoutSeconds = 300,

        [switch]$AsDataTable,

        [System.Management.Automation.PSCredential]$Credential
    )

    $cs = Get-SqlConnectionString -Server $Server -Database $Database -Credential $Credential
    $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText    = $Query
        $cmd.CommandTimeout = $TimeoutSeconds

        # Parametrage securise
        foreach ($cle in $Parameters.Keys) {
            $valeur = $Parameters[$cle]
            if ($null -eq $valeur) { $valeur = [System.DBNull]::Value }
            [void]$cmd.Parameters.AddWithValue(("@{0}" -f $cle), $valeur)
        }

        $adaptateur = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $table = New-Object System.Data.DataTable
        [void]$adaptateur.Fill($table)

        $chrono.Stop()
        Write-Verbose ("Requete executee : {0} lignes en {1:N1}s" -f $table.Rows.Count, $chrono.Elapsed.TotalSeconds)

        if ($AsDataTable) { return ,$table }     # la virgule empeche le deballage du tableau

        # Conversion en PSCustomObject pour exploitation dans le pipeline
        $colonnes = $table.Columns | ForEach-Object { $_.ColumnName }
        foreach ($ligne in $table.Rows) {
            $obj = [ordered]@{}
            foreach ($c in $colonnes) {
                $v = $ligne[$c]
                $obj[$c] = if ($v -is [System.DBNull]) { $null } else { $v }
            }
            [PSCustomObject]$obj
        }
    }
    catch [System.Data.SqlClient.SqlException] {
        Write-Log -Message ("Erreur SQL {0} : {1}" -f $_.Exception.Number, $_.Exception.Message) -Level ERROR
        throw
    }
    finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}


function Invoke-SqlNonQuery {
    <#
    .SYNOPSIS
        Execute une commande SQL sans resultat (INSERT, UPDATE, DELETE, DDL).
    .DESCRIPTION
        Renvoie le nombre de lignes affectees.
        Supporte -WhatIf pour simuler sans executer : reflexe indispensable
        avant tout UPDATE ou DELETE en production.
    .PARAMETER Server
        Instance SQL Server.
    .PARAMETER Database
        Base de donnees.
    .PARAMETER Query
        Commande SQL.
    .PARAMETER Parameters
        Parametres securises.
    .PARAMETER TimeoutSeconds
        Delai d'execution.
    .PARAMETER Credential
        Identifiants SQL (optionnel).
    .EXAMPLE
        Invoke-SqlNonQuery -Server 'SRV' -Database 'DWH' `
            -Query 'DELETE FROM dbo.Staging WHERE DateChargement < @d' `
            -Parameters @{ d = (Get-Date).AddDays(-30) } -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [hashtable]$Parameters = @{},

        [int]$TimeoutSeconds = 300,

        [System.Management.Automation.PSCredential]$Credential
    )

    $cible = "{0}\{1}" -f $Server, $Database

    # Apercu de la requete pour le message -WhatIf (tronque a 80 caracteres).
    # La longueur est calculee APRES le remplacement, sinon Substring depasse les bornes.
    $apercu = $Query -replace '\s+', ' '
    if ($apercu.Length -gt 80) { $apercu = $apercu.Substring(0, 80) }
    $action = "Executer : {0}" -f $apercu

    if (-not $PSCmdlet.ShouldProcess($cible, $action)) { return 0 }

    $cs = Get-SqlConnectionString -Server $Server -Database $Database -Credential $Credential
    $conn = New-Object System.Data.SqlClient.SqlConnection($cs)

    try {
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText    = $Query
        $cmd.CommandTimeout = $TimeoutSeconds

        foreach ($cle in $Parameters.Keys) {
            $valeur = $Parameters[$cle]
            if ($null -eq $valeur) { $valeur = [System.DBNull]::Value }
            [void]$cmd.Parameters.AddWithValue(("@{0}" -f $cle), $valeur)
        }

        $affectees = $cmd.ExecuteNonQuery()
        Write-Log -Message ("Commande executee : {0} ligne(s) affectee(s)" -f $affectees) -Level SUCCESS
        return $affectees
    }
    catch [System.Data.SqlClient.SqlException] {
        Write-Log -Message ("Erreur SQL {0} : {1}" -f $_.Exception.Number, $_.Exception.Message) -Level ERROR
        throw
    }
    finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}


function Import-ToSqlTable {
    <#
    .SYNOPSIS
        Charge massivement des donnees dans une table SQL Server (SqlBulkCopy).
    .DESCRIPTION
        SqlBulkCopy est 100 a 1000 fois plus rapide qu'une boucle d'INSERT :
        il utilise le meme mecanisme que BULK INSERT, en streaming.
        C'est LA methode a utiliser pour alimenter une table de staging DWH.

        La table de destination doit exister et ses colonnes doivent correspondre
        (par nom) a celles des donnees fournies.
    .PARAMETER InputObject
        Donnees a charger (objets PowerShell ou DataTable).
    .PARAMETER Server
        Instance SQL Server.
    .PARAMETER Database
        Base de donnees.
    .PARAMETER TableName
        Table de destination, schema compris (ex : dbo.Staging_Clients).
    .PARAMETER BatchSize
        Nombre de lignes par lot (defaut 5000).
    .PARAMETER TimeoutSeconds
        Delai (defaut 600 s).
    .PARAMETER TruncateFirst
        Vide la table avant chargement.
    .PARAMETER Credential
        Identifiants SQL (optionnel).
    .EXAMPLE
        Import-Csv .\clients.csv | Import-ToSqlTable -Server 'SRV' -Database 'DWH' `
            -TableName 'dbo.Staging_Clients' -TruncateFirst
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TableName,

        [ValidateRange(1, 1000000)]
        [int]$BatchSize = 5000,

        [int]$TimeoutSeconds = 600,

        [switch]$TruncateFirst,

        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        $tampon = New-Object 'System.Collections.Generic.List[PSObject]'
    }

    process {
        foreach ($o in $InputObject) { $tampon.Add($o) }
    }

    end {
        if ($tampon.Count -eq 0) {
            Write-Warning "Aucune donnee a charger"
            return
        }

        $cible = "{0}\{1}.{2}" -f $Server, $Database, $TableName
        if (-not $PSCmdlet.ShouldProcess($cible, ("Charger {0} lignes" -f $tampon.Count))) {
            return
        }

        # Construction du DataTable a partir des objets
        $table = New-Object System.Data.DataTable
        $colonnes = $tampon[0].PSObject.Properties.Name
        foreach ($c in $colonnes) {
            [void]$table.Columns.Add($c)
        }

        foreach ($o in $tampon) {
            $ligne = $table.NewRow()
            foreach ($c in $colonnes) {
                $v = $o.$c
                $ligne[$c] = if ($null -eq $v) { [System.DBNull]::Value } else { $v }
            }
            $table.Rows.Add($ligne)
        }

        $cs = Get-SqlConnectionString -Server $Server -Database $Database -Credential $Credential

        if ($TruncateFirst) {
            Invoke-SqlNonQuery -Server $Server -Database $Database `
                -Query ("TRUNCATE TABLE {0}" -f $TableName) `
                -Credential $Credential -Confirm:$false | Out-Null
        }

        $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($cs)
        $chrono = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $bulk.DestinationTableName = $TableName
            $bulk.BatchSize            = $BatchSize
            $bulk.BulkCopyTimeout      = $TimeoutSeconds

            # Correspondance explicite des colonnes par nom :
            # evite les erreurs si l'ordre differe entre source et destination
            foreach ($c in $colonnes) {
                [void]$bulk.ColumnMappings.Add($c, $c)
            }

            $bulk.WriteToServer($table)
            $chrono.Stop()

            Write-Log -Message ("Chargement termine : {0} lignes -> {1} en {2:N1}s" -f
                $table.Rows.Count, $TableName, $chrono.Elapsed.TotalSeconds) -Level SUCCESS
        }
        catch {
            Write-Log -Message ("Echec du chargement : {0}" -f $_.Exception.Message) -Level ERROR
            throw
        }
        finally {
            $bulk.Close()
        }
    }
}


function Get-SqlTableSchema {
    <#
    .SYNOPSIS
        Renvoie la structure d'une table SQL Server.
    .DESCRIPTION
        Permet de connaitre les colonnes, types et contraintes avant de
        construire un chargement, sans ouvrir SSMS.
    .PARAMETER Server
        Instance SQL Server.
    .PARAMETER Database
        Base de donnees.
    .PARAMETER TableName
        Nom de la table (sans le schema).
    .PARAMETER Schema
        Schema (defaut dbo).
    .EXAMPLE
        Get-SqlTableSchema -Server 'SRV' -Database 'DWH' -TableName 'Clients'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [string]$Schema = 'dbo'
    )

    $sql = @'
SELECT
    c.ORDINAL_POSITION      AS Position,
    c.COLUMN_NAME           AS Colonne,
    c.DATA_TYPE             AS Type,
    c.CHARACTER_MAXIMUM_LENGTH AS Longueur,
    c.NUMERIC_PRECISION     AS Precision,
    c.NUMERIC_SCALE         AS Echelle,
    c.IS_NULLABLE           AS Nullable,
    c.COLUMN_DEFAULT        AS ValeurDefaut
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_NAME = @tbl AND c.TABLE_SCHEMA = @sch
ORDER BY c.ORDINAL_POSITION
'@

    Invoke-SqlQuery -Server $Server -Database $Database -Query $sql `
        -Parameters @{ tbl = $TableName; sch = $Schema }
}


# ##############################################################################
# 8. GESTION DE FICHIERS / CLASSEMENT
# ##############################################################################

function Get-FileInventory {
    <#
    .SYNOPSIS
        Inventorie les fichiers d'une arborescence avec leurs caracteristiques.
    .DESCRIPTION
        Point de depart de tout travail de classement : savoir ce qu'on a,
        ou, depuis quand et en quelle quantite.
        Le resultat s'exporte directement en CSV ou Excel pour analyse.
    .PARAMETER Path
        Dossier a inventorier.
    .PARAMETER Filter
        Filtre de nom (defaut *). Applique a la source = performant.
    .PARAMETER Recurse
        Descend dans les sous-dossiers.
    .PARAMETER MinSizeMB
        Ne retient que les fichiers depassant cette taille.
    .PARAMETER OlderThanDays
        Ne retient que les fichiers plus anciens que N jours.
    .EXAMPLE
        Get-FileInventory -Path C:\Exports -Recurse | Export-CsvFast -Path .\inventaire.csv
    .EXAMPLE
        Get-FileInventory -Path D:\Data -Recurse -MinSizeMB 100 | Sort-Object TailleMo -Descending
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$Path,

        [string]$Filter = '*',

        [switch]$Recurse,

        [double]$MinSizeMB = 0,

        [int]$OlderThanDays = 0
    )

    $params = @{ Path = $Path; Filter = $Filter; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params['Recurse'] = $true }

    $limiteDate = if ($OlderThanDays -gt 0) { (Get-Date).AddDays(-$OlderThanDays) } else { $null }

    Get-ChildItem @params | ForEach-Object {

        $tailleMo = $_.Length / 1MB

        if ($MinSizeMB -gt 0 -and $tailleMo -lt $MinSizeMB) { return }
        if ($limiteDate -and $_.LastWriteTime -ge $limiteDate) { return }

        [PSCustomObject]@{
            Nom          = $_.Name
            Extension    = $_.Extension.ToLowerInvariant()
            TailleMo     = [math]::Round($tailleMo, 3)
            DateModif    = $_.LastWriteTime
            AgeJours     = [int]((Get-Date) - $_.LastWriteTime).TotalDays
            Dossier      = $_.DirectoryName
            CheminComplet = $_.FullName
            LectureSeule = $_.IsReadOnly
        }
    }
}


function Find-DuplicateFile {
    <#
    .SYNOPSIS
        Detecte les fichiers en double par leur contenu (empreinte MD5/SHA).
    .DESCRIPTION
        Optimisation importante : les empreintes ne sont calculees QUE pour les
        fichiers ayant une taille identique. Sur un disque de milliers de
        fichiers, cela evite des heures de calcul inutile.
    .PARAMETER Path
        Dossier a analyser.
    .PARAMETER Recurse
        Descend dans les sous-dossiers.
    .PARAMETER Filter
        Filtre de nom.
    .PARAMETER Algorithm
        MD5 (rapide, defaut) ou SHA256 (plus sur).
    .EXAMPLE
        Find-DuplicateFile -Path C:\Exports -Recurse | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [switch]$Recurse,

        [string]$Filter = '*',

        [ValidateSet('MD5', 'SHA1', 'SHA256')]
        [string]$Algorithm = 'MD5'
    )

    $params = @{ Path = $Path; Filter = $Filter; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params['Recurse'] = $true }

    $fichiers = Get-ChildItem @params

    # Etape 1 : regroupement par taille (tres rapide, aucune lecture de contenu)
    $parTaille = $fichiers | Group-Object Length | Where-Object { $_.Count -gt 1 }

    if (-not $parTaille) {
        Write-Verbose "Aucun fichier de taille identique : pas de doublon possible"
        return
    }

    Write-Verbose ("{0} groupes de taille identique a verifier" -f @($parTaille).Count)

    # Etape 2 : empreinte uniquement sur les candidats
    $parEmpreinte = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[object]]'

    foreach ($groupe in $parTaille) {
        foreach ($f in $groupe.Group) {
            try {
                $empreinte = (Get-FileHash -LiteralPath $f.FullName -Algorithm $Algorithm).Hash
            }
            catch {
                Write-Warning ("Empreinte impossible : {0}" -f $f.FullName)
                continue
            }

            if (-not $parEmpreinte.ContainsKey($empreinte)) {
                $parEmpreinte[$empreinte] = New-Object 'System.Collections.Generic.List[object]'
            }
            $parEmpreinte[$empreinte].Add($f)
        }
    }

    # Etape 3 : restitution des doublons averes
    foreach ($empreinte in $parEmpreinte.Keys) {
        $groupe = $parEmpreinte[$empreinte]
        if ($groupe.Count -le 1) { continue }

        $original = $groupe | Sort-Object LastWriteTime | Select-Object -First 1

        foreach ($f in $groupe) {
            [PSCustomObject]@{
                Empreinte   = $empreinte.Substring(0, 12)
                Nom         = $f.Name
                TailleMo    = [math]::Round($f.Length / 1MB, 3)
                DateModif   = $f.LastWriteTime
                EstOriginal = ($f.FullName -eq $original.FullName)
                Chemin      = $f.FullName
            }
        }
    }
}


function Move-FileByRule {
    <#
    .SYNOPSIS
        Classe automatiquement des fichiers dans des sous-dossiers selon des regles.
    .DESCRIPTION
        Automatise le rangement d'un dossier de depot :
          - par extension     : Rapports\xlsx, Rapports\csv
          - par date          : Archives\2026\08
          - par motif de nom  : regles personnalisees (regex -> dossier)

        Toujours tester avec -WhatIf avant execution reelle.
    .PARAMETER Path
        Dossier source.
    .PARAMETER Destination
        Dossier racine de destination (defaut : le dossier source).
    .PARAMETER Mode
        ByExtension, ByDate, ByPattern.
    .PARAMETER DateFormat
        Structure des sous-dossiers en mode ByDate (defaut 'yyyy\\MM').
    .PARAMETER PatternRules
        En mode ByPattern : hashtable regex -> nom de sous-dossier.
        Ex : @{ '^FACT_' = 'Factures'; '^CMD_' = 'Commandes' }
    .PARAMETER Copy
        Copie au lieu de deplacer.
    .EXAMPLE
        Move-FileByRule -Path C:\Depot -Mode ByExtension -WhatIf
    .EXAMPLE
        Move-FileByRule -Path C:\Depot -Mode ByPattern `
            -PatternRules @{ '^FACT_' = 'Factures'; '\.log$' = 'Logs' }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ByExtension', 'ByDate', 'ByPattern')]
        [string]$Mode,

        [string]$DateFormat = 'yyyy\\MM',

        [hashtable]$PatternRules = @{},

        [switch]$Copy
    )

    if (-not $Destination) { $Destination = $Path }

    if ($Mode -eq 'ByPattern' -and $PatternRules.Count -eq 0) {
        throw "Le mode ByPattern necessite le parametre -PatternRules"
    }

    # Pre-compilation des regex du mode ByPattern
    $reglesCompilees = New-Object 'System.Collections.Generic.List[object]'
    if ($Mode -eq 'ByPattern') {
        foreach ($motif in $PatternRules.Keys) {
            $reglesCompilees.Add([PSCustomObject]@{
                Regex   = New-Object System.Text.RegularExpressions.Regex(
                            $motif, [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')
                Dossier = $PatternRules[$motif]
            })
        }
    }

    $traites = 0
    $ignores = 0

    foreach ($f in Get-ChildItem -LiteralPath $Path -File) {

        # Determination du sous-dossier cible
        $sousDossier = switch ($Mode) {
            'ByExtension' {
                $e = $f.Extension.TrimStart('.').ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($e)) { 'SansExtension' } else { $e }
            }
            'ByDate' {
                $f.LastWriteTime.ToString($DateFormat)
            }
            'ByPattern' {
                $trouve = $null
                foreach ($r in $reglesCompilees) {
                    if ($r.Regex.IsMatch($f.Name)) { $trouve = $r.Dossier; break }
                }
                $trouve
            }
        }

        if (-not $sousDossier) {
            $ignores++
            Write-Verbose ("Aucune regle applicable : {0}" -f $f.Name)
            continue
        }

        $dossierCible = Join-Path -Path $Destination -ChildPath $sousDossier
        $cheminCible  = Join-Path -Path $dossierCible -ChildPath $f.Name

        $action = if ($Copy) { 'Copier' } else { 'Deplacer' }

        if ($PSCmdlet.ShouldProcess($f.FullName, ("{0} vers {1}" -f $action, $dossierCible))) {

            if (-not (Test-Path -LiteralPath $dossierCible)) {
                New-Item -Path $dossierCible -ItemType Directory -Force | Out-Null
            }

            # Gestion des collisions de noms : suffixe incremental
            if (Test-Path -LiteralPath $cheminCible) {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                $ext  = $f.Extension
                $i = 1
                do {
                    $nouveauNom = "{0}_{1}{2}" -f $base, $i, $ext
                    $cheminCible = Join-Path -Path $dossierCible -ChildPath $nouveauNom
                    $i++
                } while (Test-Path -LiteralPath $cheminCible)
            }

            if ($Copy) {
                Copy-Item -LiteralPath $f.FullName -Destination $cheminCible
            }
            else {
                Move-Item -LiteralPath $f.FullName -Destination $cheminCible
            }
            $traites++
        }
    }

    Write-Log -Message ("Classement termine : {0} traite(s), {1} ignore(s)" -f $traites, $ignores) -Level SUCCESS
}


function Backup-File {
    <#
    .SYNOPSIS
        Cree une copie horodatee d'un fichier avant modification.
    .DESCRIPTION
        Reflexe indispensable avant tout traitement destructeur.
        Le nom de la sauvegarde contient la date et l'heure, ce qui
        permet de conserver plusieurs versions successives.
    .PARAMETER Path
        Fichier a sauvegarder.
    .PARAMETER BackupFolder
        Dossier des sauvegardes (defaut : sous-dossier _backup a cote du fichier).
    .PARAMETER MaxBackups
        Conserve au maximum N sauvegardes (les plus anciennes sont supprimees).
    .EXAMPLE
        Backup-File -Path C:\CRE\CRE.xlsx -MaxBackups 5
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path,

        [string]$BackupFolder,

        [ValidateRange(0, 1000)]
        [int]$MaxBackups = 0
    )

    $source = Get-Item -LiteralPath $Path

    if (-not $BackupFolder) {
        $BackupFolder = Join-Path -Path $source.DirectoryName -ChildPath '_backup'
    }
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($source.Name)
    $horodatage = Get-Date -Format 'yyyyMMdd_HHmmss'
    $nomSauvegarde = "{0}_{1}{2}" -f $base, $horodatage, $source.Extension
    $cheminSauvegarde = Join-Path -Path $BackupFolder -ChildPath $nomSauvegarde

    if ($PSCmdlet.ShouldProcess($cheminSauvegarde, 'Creer la sauvegarde')) {
        Copy-Item -LiteralPath $source.FullName -Destination $cheminSauvegarde
        Write-Log -Message ("Sauvegarde : {0}" -f $cheminSauvegarde) -Level SUCCESS
    }

    # Rotation : suppression des sauvegardes excedentaires
    if ($MaxBackups -gt 0) {
        $motif = "{0}_*{1}" -f $base, $source.Extension
        $anciennes = Get-ChildItem -LiteralPath $BackupFolder -Filter $motif -File |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -Skip $MaxBackups

        foreach ($a in $anciennes) {
            if ($PSCmdlet.ShouldProcess($a.FullName, 'Supprimer ancienne sauvegarde')) {
                Remove-Item -LiteralPath $a.FullName -Force
                Write-Verbose ("Sauvegarde supprimee : {0}" -f $a.Name)
            }
        }
    }

    return $cheminSauvegarde
}


function Remove-OldFile {
    <#
    .SYNOPSIS
        Supprime les fichiers plus anciens qu'un nombre de jours donne.
    .DESCRIPTION
        Purge de dossiers d'archives, de logs ou de fichiers temporaires.
        ATTENTION : operation destructrice. Utilisez systematiquement -WhatIf
        pour verifier la liste avant execution reelle.
    .PARAMETER Path
        Dossier a purger.
    .PARAMETER DaysOld
        Age minimum en jours pour la suppression.
    .PARAMETER Filter
        Filtre de nom (defaut *).
    .PARAMETER Recurse
        Descend dans les sous-dossiers.
    .EXAMPLE
        Remove-OldFile -Path C:\Logs -DaysOld 90 -Filter *.log -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$DaysOld,

        [string]$Filter = '*',

        [switch]$Recurse
    )

    $limite = (Get-Date).AddDays(-$DaysOld)
    $params = @{ Path = $Path; Filter = $Filter; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params['Recurse'] = $true }

    $supprimes = 0
    $octetsLiberes = [long]0

    foreach ($f in Get-ChildItem @params) {
        if ($f.LastWriteTime -ge $limite) { continue }

        if ($PSCmdlet.ShouldProcess($f.FullName, ("Supprimer (modifie le {0:yyyy-MM-dd})" -f $f.LastWriteTime))) {
            $taille = $f.Length
            try {
                Remove-Item -LiteralPath $f.FullName -Force
                $supprimes++
                $octetsLiberes += $taille
            }
            catch {
                Write-Warning ("Suppression impossible : {0}" -f $f.FullName)
            }
        }
    }

    Write-Log -Message ("Purge : {0} fichier(s) supprime(s), {1:N1} Mo liberes" -f
        $supprimes, ($octetsLiberes / 1MB)) -Level SUCCESS
}


# ##############################################################################
# 9. UTILITAIRES
# ##############################################################################

function New-Timer {
    <#
    .SYNOPSIS
        Demarre un chronometre pour mesurer une duree de traitement.
    .DESCRIPTION
        A utiliser avec Get-Timing pour instrumenter vos scripts et
        identifier les etapes lentes.
    .EXAMPLE
        $t = New-Timer
        # ... traitement ...
        Get-Timing -Timer $t -Label 'Import CSV'
    #>
    [CmdletBinding()]
    param()
    return [System.Diagnostics.Stopwatch]::StartNew()
}


function Get-Timing {
    <#
    .SYNOPSIS
        Affiche la duree ecoulee depuis le demarrage d'un chronometre.
    .PARAMETER Timer
        Chronometre cree par New-Timer.
    .PARAMETER Label
        Libelle de l'etape mesuree.
    .PARAMETER Reset
        Redemarre le chronometre apres l'affichage (mesure d'etapes successives).
    .EXAMPLE
        Get-Timing -Timer $t -Label 'Chargement SQL' -Reset
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Diagnostics.Stopwatch]$Timer,

        [string]$Label = 'Etape',

        [switch]$Reset
    )

    $duree = $Timer.Elapsed
    $texte = if ($duree.TotalSeconds -lt 1) {
        "{0:N0} ms" -f $duree.TotalMilliseconds
    }
    elseif ($duree.TotalMinutes -lt 1) {
        "{0:N1} s" -f $duree.TotalSeconds
    }
    else {
        "{0:N0} min {1:N0} s" -f $duree.TotalMinutes, $duree.Seconds
    }

    Write-Log -Message ("{0} : {1}" -f $Label, $texte) -Level INFO

    if ($Reset) { $Timer.Restart() }
    return $duree
}


function Test-IsNumeric {
    <#
    .SYNOPSIS
        Verifie qu'une valeur est numerique (gere virgule et point decimal).
    .PARAMETER Value
        Valeur a tester.
    .EXAMPLE
        Test-IsNumeric -Value '1 234,56'      # True
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    process {
        if ($null -eq $Value) { return $false }

        $txt = ([string]$Value).Trim() -replace '\s', ''
        if ([string]::IsNullOrEmpty($txt)) { return $false }

        $r = [decimal]0
        $styles = [System.Globalization.NumberStyles]::Any

        # Essai avec la culture francaise (virgule decimale)
        $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        if ([decimal]::TryParse($txt, $styles, $fr, [ref]$r)) { return $true }

        # Essai avec la culture invariante (point decimal)
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        return [decimal]::TryParse(($txt -replace ',', '.'), $styles, $inv, [ref]$r)
    }
}


function ConvertTo-SafeName {
    <#
    .SYNOPSIS
        Nettoie une chaine pour en faire un nom de fichier valide.
    .DESCRIPTION
        Remplace les caracteres interdits par Windows et supprime les accents.
        Indispensable quand un nom de fichier est construit a partir de donnees
        metier (nom de client, libelle de feuille Excel...).
    .PARAMETER Name
        Nom a nettoyer.
    .PARAMETER Replacement
        Caractere de remplacement (defaut '_').
    .PARAMETER RemoveAccents
        Supprime egalement les accents.
    .EXAMPLE
        ConvertTo-SafeName -Name 'Rapport 2026/08 (final).xlsx'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$Replacement = '_',

        [switch]$RemoveAccents
    )

    process {
        $resultat = $Name

        if ($RemoveAccents) {
            # Decomposition Unicode puis suppression des marques diacritiques
            $decompose = $resultat.Normalize([System.Text.NormalizationForm]::FormD)
            $sb = New-Object System.Text.StringBuilder $decompose.Length
            foreach ($ch in $decompose.ToCharArray()) {
                $categorie = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
                if ($categorie -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
                    [void]$sb.Append($ch)
                }
            }
            $resultat = $sb.ToString()
        }

        # Remplacement des caracteres interdits par Windows
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
            $resultat = $resultat.Replace($c, $Replacement)
        }

        # Nettoyage : espaces multiples et separateurs repetes
        $resultat = $resultat -replace '\s+', ' '
        $motifRepete = "{0}{1}" -f [regex]::Escape($Replacement), '+'
        $resultat = $resultat -replace $motifRepete, $Replacement

        return $resultat.Trim()
    }
}


# ##############################################################################
# EXPORT DES FONCTIONS PUBLIQUES
# ##############################################################################

Export-ModuleMember -Function @(
    # 1. Journalisation
    'Start-LogSession', 'Stop-LogSession', 'Write-Log',
    # 2. Encodage
    'Get-FileEncoding', 'Read-TextFile', 'Write-TextFile', 'Convert-FileEncoding',
    # 3. Fichiers texte
    'Measure-FileLine', 'Search-InFile', 'Split-LargeFile', 'Get-FileHead', 'Get-FileTail',
    # 4. CSV
    'Get-CsvDelimiter', 'Import-CsvFast', 'ConvertTo-TypedObject', 'Export-CsvFast', 'Merge-CsvFile',
    # 5. Qualite de donnees
    'Get-DataProfile', 'Find-DuplicateRow', 'Compare-DataSet', 'Test-DataQuality',
    # 6. Excel
    'New-ExcelApp', 'Close-ExcelApp', 'Get-ExcelSheetName', 'Import-ExcelSheet',
    'Export-ExcelSheet', 'Convert-ExcelToCsv',
    # 7. SQL Server
    'Get-SqlConnectionString', 'Test-SqlConnection', 'Invoke-SqlQuery', 'Invoke-SqlNonQuery',
    'Import-ToSqlTable', 'Get-SqlTableSchema',
    # 8. Fichiers / classement
    'Get-FileInventory', 'Find-DuplicateFile', 'Move-FileByRule', 'Backup-File', 'Remove-OldFile',
    # 9. Utilitaires
    'New-Timer', 'Get-Timing', 'Test-IsNumeric', 'ConvertTo-SafeName'
)
