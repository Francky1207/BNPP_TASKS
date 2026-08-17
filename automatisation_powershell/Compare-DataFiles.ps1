<#
================================================================================
 Compare-DataFiles.ps1  -  Utilitaire universel de comparaison
================================================================================

 A QUOI CA SERT
 --------------
 Comparer deux sources de donnees et produire un rapport des differences
 (et optionnellement des correspondances), avec LES NUMEROS DE LIGNE.

 Sources acceptees : .txt .log .sql .xml .json .csv .tsv .xlsx .xls .xlsm

 5 MODES DE COMPARAISON
 ----------------------
  TextPositional : ligne 1 contre ligne 1, ligne 2 contre ligne 2...
                   -> pour comparer 2 versions d'un meme fichier
  TextSet        : quelles lignes sont dans A mais pas dans B (et inverse),
                   sans tenir compte de l'ordre
                   -> pour comparer 2 listes/exports
  Columns        : compare UNE colonne de A contre UNE colonne de B
                   (Excel ou CSV, meme fichier ou fichiers differents,
                    meme feuille ou feuilles differentes)
  KeyedRows      : rapprochement par cle metier, detection des lignes
                   ajoutees / supprimees / MODIFIEES champ par champ
                   -> le plus puissant pour du controle de migration
  Auto           : choisit TextPositional ou TextSet selon les fichiers

 EXEMPLES RAPIDES
 ----------------
  # 2 fichiers texte, differences avec numeros de ligne
  .\Compare-DataFiles.ps1 -Path1 a.txt -Path2 b.txt -OutputPath diff.csv

  # 2 colonnes Excel de feuilles differentes, resultat dans une nouvelle feuille
  .\Compare-DataFiles.ps1 -Path1 CRE.xlsx -Sheet1 CRE     -Column1 CRE `
                          -Path2 CRE.xlsx -Sheet2 MAPPING_CRE -Column2 CRE `
                          -Mode Columns -OutputSheet COMPARAISON

  # Controle de migration par cle
  .\Compare-DataFiles.ps1 -Path1 avant.csv -Path2 apres.csv `
                          -Mode KeyedRows -KeyColumns ID -OutputPath ecarts.csv

 PREREQUIS : Excel installe uniquement pour les fichiers .xlsx/.xls/.xlsm.
             AUCUN droit administrateur.
================================================================================
#>

[CmdletBinding()]
param(
    # ---------- SOURCES ----------
    [Parameter(Mandatory = $true)]
    [string]$Path1,

    [Parameter(Mandatory = $true)]
    [string]$Path2,

    # Feuilles Excel (ignore pour les fichiers texte)
    [string]$Sheet1 = '',
    [string]$Sheet2 = '',

    # Colonne a comparer en mode Columns.
    # Accepte : un nom d'entete (CRE), une lettre (A, B, AC) ou un index (1, 2)
    [string]$Column1 = '',
    [string]$Column2 = '',

    # ---------- MODE ----------
    [ValidateSet('Auto', 'TextPositional', 'TextSet', 'Columns', 'KeyedRows')]
    [string]$Mode = 'Auto',

    # Colonne(s) formant la cle en mode KeyedRows
    [string[]]$KeyColumns = @(),

    # Colonnes a comparer en mode KeyedRows (vide = toutes les colonnes communes)
    [string[]]$CompareColumns = @(),

    # ---------- OPTIONS DE COMPARAISON ----------
    [switch]$CaseSensitive,          # par defaut la casse est ignoree
    [switch]$NoTrim,                 # par defaut les espaces de bord sont retires
    [switch]$IgnoreEmptyLines,       # ignore les lignes vides
    [switch]$NormalizeWhitespace,    # reduit les espaces multiples a un seul
    [switch]$IgnoreAccents,          # compare sans tenir compte des accents

    # ---------- SORTIE ----------
    [string]$OutputPath = '',        # .csv .txt ou .xlsx
    [string]$OutputSheet = '',       # nom de feuille a creer dans Path1 (Excel)
    [switch]$IncludeMatches,         # inclure aussi les lignes IDENTIQUES
    [int]$MaxDifferences = 0,        # 0 = illimite
    [switch]$NoBackup,               # ne pas sauvegarder avant ecriture dans Path1

    # ---------- DIVERS ----------
    [string]$Delimiter = '',         # separateur CSV (vide = detection auto)
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'

# ##############################################################################
# BLOC 0 : TRACAGE ET DIAGNOSTIC (integre, aucune dependance externe)
# ##############################################################################

$script:LogFile   = $LogPath
$script:StepDepth = 0
$script:StepNum   = 0
$script:StartTime = Get-Date

function Write-T {
    # Ecrit une ligne dans la console et, si demande, dans le fichier de log.
    param([string]$Text = '', [string]$Color = 'White')
    Write-Host $Text -ForegroundColor $Color
    if ($script:LogFile) {
        try {
            Add-Content -LiteralPath $script:LogFile -Encoding UTF8 `
                -Value ("{0} | {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text)
        }
        catch { }
    }
}

function Write-Etape {
    # Message a l'interieur d'une etape, indente selon le niveau d'imbrication.
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DETAIL')]
        [string]$Level = 'INFO'
    )
    $ind = '  ' * $script:StepDepth
    $sym = switch ($Level) {
        'INFO'   { '[i]' }
        'OK'     { '[+]' }
        'WARN'   { '[!]' }
        'ERROR'  { '[X]' }
        'DETAIL' { '   ' }
    }
    $col = switch ($Level) {
        'INFO'   { 'White' }
        'OK'     { 'Green' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'DETAIL' { 'Gray' }
    }
    Write-T -Text ("{0}{1} {2}" -f $ind, $sym, $Message) -Color $col
}

function Start-Etape {
    # Annonce le debut d'une etape numerotee.
    # Affectations explicites plutot que ++ : l'operateur d'incrementation sur
    # une variable de portee $script: est interprete differemment selon les versions.
    param([string]$Name)
    $script:StepNum = $script:StepNum + 1
    $ind = '  ' * $script:StepDepth
    Write-T -Text ("{0}> ETAPE {1} : {2}" -f $ind, $script:StepNum, $Name) -Color Cyan
    $script:StepDepth = $script:StepDepth + 1
    return $Name
}

function Close-Etape {
    # Cloture une etape et affiche sa duree.
    param([string]$Name, [System.Diagnostics.Stopwatch]$Chrono)
    if ($script:StepDepth -gt 0) { $script:StepDepth = $script:StepDepth - 1 }
    $ind = '  ' * $script:StepDepth
    $d = if ($Chrono) { "{0:N1}s" -f $Chrono.Elapsed.TotalSeconds } else { '' }
    Write-T -Text ("{0}< OK    {1} ({2})" -f $ind, $Name, $d) -Color Green
}

function Show-Erreur {
    # Rapport de diagnostic complet : etape, fonction, fichier, ligne, code fautif.
    param(
        [System.Management.Automation.ErrorRecord]$Err,
        [string]$Etape = '',
        [hashtable]$Contexte = @{}
    )

    $info = $Err.InvocationInfo

    $fonction = ''
    if ($info -and $info.MyCommand -and $info.MyCommand.Name) { $fonction = $info.MyCommand.Name }
    if ([string]::IsNullOrWhiteSpace($fonction) -and $Err.ScriptStackTrace) {
        $m = [regex]::Match((($Err.ScriptStackTrace -split "`n")[0]), 'at\s+([^,]+)')
        if ($m.Success) { $fonction = $m.Groups[1].Value.Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($fonction)) { $fonction = '<script principal>' }

    Write-T -Text ''
    Write-T -Text ('#' * 78) -Color Red
    Write-T -Text '#  ERREUR' -Color Red
    Write-T -Text ('#' * 78) -Color Red
    if ($Etape) { Write-T -Text ("#  ETAPE       : {0}" -f $Etape) -Color Red }
    Write-T -Text ("#  FONCTION    : {0}" -f $fonction) -Color Red
    if ($info -and $info.ScriptName) {
        Write-T -Text ("#  FICHIER     : {0}" -f (Split-Path -Path $info.ScriptName -Leaf)) -Color Red
    }
    if ($info) {
        Write-T -Text ("#  LIGNE       : {0} (colonne {1})" -f $info.ScriptLineNumber, $info.OffsetInLine) -Color Red
        if ($info.Line) { Write-T -Text ("#  CODE FAUTIF : {0}" -f $info.Line.Trim()) -Color Yellow }
    }
    Write-T -Text ("#  MESSAGE     : {0}" -f $Err.Exception.Message) -Color Red
    Write-T -Text ("#  TYPE .NET   : {0}" -f $Err.Exception.GetType().FullName) -Color Red

    $ex = $Err.Exception.InnerException
    $n = 0
    while ($null -ne $ex -and $n -lt 4) {
        $n = $n + 1
        Write-T -Text ("#  INTERNE {0}   : {1} : {2}" -f $n, $ex.GetType().Name, $ex.Message) -Color DarkYellow
        $ex = $ex.InnerException
    }

    if ($Contexte -and $Contexte.Count -gt 0) {
        Write-T -Text ('#' + ('-' * 77)) -Color Red
        Write-T -Text '#  CONTEXTE :' -Color Red
        foreach ($cle in $Contexte.Keys) {
            $v = $Contexte[$cle]
            $t = if ($null -eq $v) { '<null>' } else { [string]$v }
            if ($t.Length -gt 90) { $t = $t.Substring(0, 90) }
            Write-T -Text ("#    {0} = {1}" -f $cle, $t) -Color DarkYellow
        }
    }

    if ($Err.ScriptStackTrace) {
        Write-T -Text ('#' + ('-' * 77)) -Color Red
        Write-T -Text '#  PILE D''APPEL :' -Color Red
        foreach ($l in ($Err.ScriptStackTrace -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($l)) {
                Write-T -Text ("#    {0}" -f $l.Trim()) -Color DarkGray
            }
        }
    }
    Write-T -Text ('#' * 78) -Color Red
    Write-T -Text ''
}


# ##############################################################################
# BLOC 1 : NORMALISATION DES VALEURS
# ##############################################################################

function Get-ValeurNormalisee {
    <#
        Applique les options de comparaison a une valeur.
        C'est CETTE valeur qui sert a comparer ; la valeur d'origine est
        toujours conservee a part pour l'affichage dans le rapport.
    #>
    param([object]$Valeur)

    if ($null -eq $Valeur) { return '' }
    $t = [string]$Valeur

    if (-not $NoTrim) { $t = $t.Trim() }
    if ($NormalizeWhitespace) { $t = ($t -replace '\s+', ' ').Trim() }

    if ($IgnoreAccents) {
        # Decomposition Unicode puis suppression des marques diacritiques
        $d = $t.Normalize([System.Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder $d.Length
        foreach ($ch in $d.ToCharArray()) {
            $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
            if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        $t = $sb.ToString()
    }

    if (-not $CaseSensitive) { $t = $t.ToUpperInvariant() }

    return $t
}

function Get-Comparateur {
    # Renvoie le comparateur de chaines adapte aux options choisies.
    # Utilise pour les HashSet et Dictionary : garantit la coherence.
    if ($CaseSensitive) { return [StringComparer]::Ordinal }
    return [StringComparer]::OrdinalIgnoreCase
}


# ##############################################################################
# BLOC 2 : LECTURE DES SOURCES
# ##############################################################################

function Get-TypeFichier {
    # Determine le type de traitement d'apres l'extension.
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.xlsx' { return 'EXCEL' }
        '.xlsm' { return 'EXCEL' }
        '.xls'  { return 'EXCEL' }
        '.xlsb' { return 'EXCEL' }
        '.csv'  { return 'CSV' }
        '.tsv'  { return 'CSV' }
        default { return 'TEXTE' }
    }
}

function Get-SeparateurCsv {
    <#
        Detecte le separateur d'un CSV en analysant les premieres lignes :
        on retient le caractere le plus frequent ET le plus regulier.
    #>
    param([string]$Path)

    if ($Delimiter) { return $Delimiter }

    $candidats = @(';', ',', "`t", '|')
    $lignes = New-Object 'System.Collections.Generic.List[string]'

    $lecteur = New-Object System.IO.StreamReader($Path)
    try {
        for ($i = 0; $i -lt 5; $i++) {
            $l = $lecteur.ReadLine()
            if ($null -eq $l) { break }
            if (-not [string]::IsNullOrWhiteSpace($l)) { $lignes.Add($l) }
        }
    }
    finally { $lecteur.Dispose() }

    if ($lignes.Count -eq 0) { return ';' }

    $meilleur = ';'
    $meilleurScore = -1

    foreach ($sep in $candidats) {
        $comptes = New-Object 'System.Collections.Generic.List[int]'
        foreach ($l in $lignes) {
            $n = 0
            foreach ($ch in $l.ToCharArray()) { if ($ch -eq $sep) { $n = $n + 1 } }
            $comptes.Add($n)
        }
        $moyenne = ($comptes | Measure-Object -Average).Average
        if ($moyenne -lt 1) { continue }
        $regulier = (($comptes | Select-Object -Unique).Count -eq 1)
        $score = if ($regulier) { $moyenne * 10 } else { $moyenne }
        if ($score -gt $meilleurScore) { $meilleurScore = $score; $meilleur = $sep }
    }

    return $meilleur
}

function Read-LignesTexte {
    <#
        Lit un fichier texte ligne par ligne EN FLUX (StreamReader).
        La memoire reste constante quelle que soit la taille du fichier :
        indispensable au-dela de quelques centaines de Mo.
        Chaque element conserve son NUMERO DE LIGNE d'origine.
    #>
    param([string]$Path)

    $resultat = New-Object 'System.Collections.Generic.List[object]'
    $numero = 0

    $lecteur = New-Object System.IO.StreamReader($Path)
    try {
        while ($null -ne ($ligne = $lecteur.ReadLine())) {
            $numero = $numero + 1
            if ($IgnoreEmptyLines -and [string]::IsNullOrWhiteSpace($ligne)) { continue }
            $resultat.Add([PSCustomObject]@{
                Numero    = $numero
                Brut      = $ligne
                Normalise = (Get-ValeurNormalisee -Valeur $ligne)
            })
        }
    }
    finally { $lecteur.Dispose() }

    # La virgule empeche PowerShell de "deballer" la collection :
    # sans elle, une liste vide devient $null et une liste d'1 element
    # devient un objet simple, ce qui casse .Count et l'indexation.
    return ,$resultat
}

function Resolve-IndexColonne {
    <#
        Convertit une designation de colonne en index numerique.
        Accepte :
          - un nom d'entete       : "CRE"
          - une lettre Excel      : "A", "B", "AC"
          - un index numerique    : "1", "3"
        Renvoie 0 si non trouvee.
    #>
    param(
        [string]$Designation,
        [hashtable]$MapEntetes,     # NOM_MAJUSCULE -> index
        [int]$ColMin,
        [int]$ColMax
    )

    if ([string]::IsNullOrWhiteSpace($Designation)) { return 0 }
    $d = $Designation.Trim()

    # 1. Nom d'entete (prioritaire : le plus explicite)
    $cle = $d.ToUpperInvariant()
    if ($MapEntetes.ContainsKey($cle)) { return $MapEntetes[$cle] }

    # 2. Index numerique
    $n = 0
    if ([int]::TryParse($d, [ref]$n)) {
        if ($n -ge $ColMin -and $n -le $ColMax) { return $n }
        return 0
    }

    # 3. Lettre de colonne Excel : A=1, B=2, ... Z=26, AA=27
    if ($d -match '^[A-Za-z]{1,3}$') {
        $index = 0
        foreach ($ch in $d.ToUpperInvariant().ToCharArray()) {
            $index = $index * 26 + ([int][char]$ch - 64)
        }
        if ($index -ge $ColMin -and $index -le $ColMax) { return $index }
    }

    return 0
}

function Read-ExcelSheet {
    <#
        Ouvre un classeur en LECTURE SEULE et renvoie le tableau 2D de la
        feuille demandee. Lecture en UN SEUL appel COM (UsedRange.Value2) :
        environ 100x plus rapide qu'une lecture cellule par cellule.

        L'acces au tableau se fait ensuite via .GetValue(ligne, colonne) :
        la syntaxe $tab[$l,$c] est ambigue selon les versions de PowerShell.
    #>
    param([string]$Path, [string]$SheetName)

    $chemin = (Resolve-Path -LiteralPath $Path).Path
    $excel = $null
    $wb = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible        = $false
        $excel.DisplayAlerts  = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents   = $false

        $wb = $excel.Workbooks.Open($chemin, 0, $true)   # ReadOnly = true

        $ws = $null
        if ($SheetName) {
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $SheetName) { $ws = $s; break }
            }
            if ($null -eq $ws) {
                $dispo = New-Object 'System.Collections.Generic.List[string]'
                foreach ($s in $wb.Worksheets) { $dispo.Add($s.Name) }
                throw ("Feuille '{0}' introuvable dans {1}. Feuilles disponibles : {2}" -f
                       $SheetName, (Split-Path -Path $Path -Leaf), ($dispo -join ', '))
            }
        }
        else {
            $ws = $wb.Worksheets.Item(1)
            Write-Etape -Message ("Feuille non precisee, utilisation de '{0}'" -f $ws.Name) -Level DETAIL
        }

        $data = $ws.UsedRange.Value2
        if ($data -isnot [System.Array]) {
            throw ("La feuille '{0}' de {1} est vide" -f $ws.Name, (Split-Path -Path $Path -Leaf))
        }

        # Construction de la table des entetes (1re ligne)
        $rMin = [int]$data.GetLowerBound(0)
        $cMin = [int]$data.GetLowerBound(1)
        $cMax = [int]$data.GetUpperBound(1)

        $entetes = @{}
        for ($c = $cMin; $c -le $cMax; $c++) {
            $v = $data.GetValue($rMin, $c)
            if ($null -eq $v) { continue }
            $nom = ([string]$v).Trim().ToUpperInvariant()
            if ($nom -and -not $entetes.ContainsKey($nom)) { $entetes[$nom] = $c }
        }

        return [PSCustomObject]@{
            Data      = $data
            SheetName = $ws.Name
            RowMin    = $rMin
            RowMax    = [int]$data.GetUpperBound(0)
            ColMin    = $cMin
            ColMax    = $cMax
            Entetes   = $entetes
        }
    }
    finally {
        # Liberation COM systematique : sinon EXCEL.EXE reste en memoire
        if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
        if ($excel) { try { $excel.Quit() } catch { } }
        foreach ($o in @($wb, $excel)) {
            if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Read-Colonne {
    <#
        Renvoie les valeurs d'UNE colonne, avec leur numero de ligne d'origine.
        Fonctionne indifferemment sur Excel, CSV ou fichier texte delimite.
    #>
    param(
        [string]$Path,
        [string]$SheetName,
        [string]$Designation,
        [string]$Libelle          # pour les messages d'erreur
    )

    $type = Get-TypeFichier -Path $Path
    $valeurs = New-Object 'System.Collections.Generic.List[object]'

    if ($type -eq 'EXCEL') {
        $info = Read-ExcelSheet -Path $Path -SheetName $SheetName

        $idx = Resolve-IndexColonne -Designation $Designation -MapEntetes $info.Entetes `
                                    -ColMin $info.ColMin -ColMax $info.ColMax
        if ($idx -eq 0) {
            throw ("{0} : colonne '{1}' introuvable dans la feuille '{2}'. Entetes disponibles : {3}" -f
                   $Libelle, $Designation, $info.SheetName,
                   (($info.Entetes.Keys | Sort-Object) -join ', '))
        }

        Write-Etape -Message ("{0} : feuille '{1}', colonne '{2}' -> index {3}" -f
            $Libelle, $info.SheetName, $Designation, $idx) -Level DETAIL

        # On demarre a RowMin+1 : la premiere ligne est l'entete
        for ($r = $info.RowMin + 1; $r -le $info.RowMax; $r++) {
            $v = $info.Data.GetValue($r, $idx)
            $brut = if ($null -eq $v) { '' } else { [string]$v }
            if ($IgnoreEmptyLines -and [string]::IsNullOrWhiteSpace($brut)) { continue }
            $valeurs.Add([PSCustomObject]@{
                Numero    = $r
                Brut      = $brut
                Normalise = (Get-ValeurNormalisee -Valeur $brut)
            })
        }
    }
    else {
        # CSV ou texte delimite
        $sep = Get-SeparateurCsv -Path $Path
        $lignes = Read-LignesTexte -Path $Path
        if ($lignes.Count -eq 0) { throw ("{0} : fichier vide" -f $Libelle) }

        # Entetes = premiere ligne
        $entetes = @{}
        $champsEntete = $lignes[0].Brut -split ([regex]::Escape($sep))
        for ($i = 0; $i -lt $champsEntete.Count; $i++) {
            $nom = $champsEntete[$i].Trim().Trim('"').ToUpperInvariant()
            if ($nom -and -not $entetes.ContainsKey($nom)) { $entetes[$nom] = $i + 1 }
        }

        $idx = Resolve-IndexColonne -Designation $Designation -MapEntetes $entetes `
                                    -ColMin 1 -ColMax $champsEntete.Count
        if ($idx -eq 0) {
            throw ("{0} : colonne '{1}' introuvable. Entetes disponibles : {2}" -f
                   $Libelle, $Designation, (($entetes.Keys | Sort-Object) -join ', '))
        }

        Write-Etape -Message ("{0} : colonne '{1}' -> position {2}" -f $Libelle, $Designation, $idx) -Level DETAIL

        for ($i = 1; $i -lt $lignes.Count; $i++) {
            $champs = $lignes[$i].Brut -split ([regex]::Escape($sep))
            $brut = if ($idx -le $champs.Count) { $champs[$idx - 1].Trim().Trim('"') } else { '' }
            if ($IgnoreEmptyLines -and [string]::IsNullOrWhiteSpace($brut)) { continue }
            $valeurs.Add([PSCustomObject]@{
                Numero    = $lignes[$i].Numero
                Brut      = $brut
                Normalise = (Get-ValeurNormalisee -Valeur $brut)
            })
        }
    }

    # La virgule empeche PowerShell de "deballer" la collection :
    # sans elle, une liste vide devient $null et une liste d'1 element
    # devient un objet simple, ce qui casse .Count et l'indexation.
    return ,$valeurs
}

function Read-LignesStructurees {
    <#
        Lit une source tabulaire (Excel ou CSV) sous forme de lignes-objets
        avec leur numero de ligne. Utilise par le mode KeyedRows.
    #>
    param([string]$Path, [string]$SheetName, [string]$Libelle)

    $type = Get-TypeFichier -Path $Path
    $lignes = New-Object 'System.Collections.Generic.List[object]'
    $colonnes = New-Object 'System.Collections.Generic.List[string]'

    if ($type -eq 'EXCEL') {
        $info = Read-ExcelSheet -Path $Path -SheetName $SheetName

        # Noms de colonnes dans l'ordre
        $indexParNom = @{}
        for ($c = $info.ColMin; $c -le $info.ColMax; $c++) {
            $v = $info.Data.GetValue($info.RowMin, $c)
            $nom = if ($null -eq $v) { ("Colonne{0}" -f $c) } else { ([string]$v).Trim() }
            if (-not $nom) { $nom = ("Colonne{0}" -f $c) }
            # Desambiguisation des doublons d'entete
            $final = $nom
            $suffixe = 1
            while ($colonnes.Contains($final)) {
                $suffixe = $suffixe + 1
                $final = "{0}_{1}" -f $nom, $suffixe
            }
            $colonnes.Add($final)
            $indexParNom[$final] = $c
        }

        for ($r = $info.RowMin + 1; $r -le $info.RowMax; $r++) {
            $valeurs = @{}
            $vide = $true
            foreach ($nom in $colonnes) {
                $v = $info.Data.GetValue($r, $indexParNom[$nom])
                $t = if ($null -eq $v) { '' } else { [string]$v }
                if ($t.Trim()) { $vide = $false }
                $valeurs[$nom] = $t
            }
            if ($vide) { continue }
            $lignes.Add([PSCustomObject]@{ Numero = $r; Valeurs = $valeurs })
        }
    }
    else {
        $sep = Get-SeparateurCsv -Path $Path
        $brutes = Read-LignesTexte -Path $Path
        if ($brutes.Count -eq 0) { throw ("{0} : fichier vide" -f $Libelle) }

        $champsEntete = $brutes[0].Brut -split ([regex]::Escape($sep))
        foreach ($ce in $champsEntete) {
            $nom = $ce.Trim().Trim('"')
            if (-not $nom) { $nom = ("Colonne{0}" -f ($colonnes.Count + 1)) }
            $final = $nom
            $suffixe = 1
            while ($colonnes.Contains($final)) {
                $suffixe = $suffixe + 1
                $final = "{0}_{1}" -f $nom, $suffixe
            }
            $colonnes.Add($final)
        }

        for ($i = 1; $i -lt $brutes.Count; $i++) {
            $champs = $brutes[$i].Brut -split ([regex]::Escape($sep))
            $valeurs = @{}
            for ($c = 0; $c -lt $colonnes.Count; $c++) {
                $valeurs[$colonnes[$c]] = if ($c -lt $champs.Count) { $champs[$c].Trim().Trim('"') } else { '' }
            }
            $lignes.Add([PSCustomObject]@{ Numero = $brutes[$i].Numero; Valeurs = $valeurs })
        }
    }

    return [PSCustomObject]@{ Lignes = $lignes; Colonnes = $colonnes }
}


# ##############################################################################
# BLOC 3 : MOTEURS DE COMPARAISON
# ##############################################################################

function New-Difference {
    # Fabrique une ligne de resultat. Structure unique pour tous les modes,
    # ce qui permet un export homogene quel que soit le type de comparaison.
    param(
        [string]$Statut,
        [object]$Ligne1 = '',
        [string]$Valeur1 = '',
        [object]$Ligne2 = '',
        [string]$Valeur2 = '',
        [string]$Cle = '',
        [string]$Colonne = '',
        [string]$Detail = ''
    )
    return [PSCustomObject]@{
        STATUT   = $Statut
        LIGNE_1  = $Ligne1
        VALEUR_1 = $Valeur1
        LIGNE_2  = $Ligne2
        VALEUR_2 = $Valeur2
        CLE      = $Cle
        COLONNE  = $Colonne
        DETAIL   = $Detail
    }
}

function Compare-Positionnel {
    <#
        Compare ligne 1 contre ligne 1, ligne 2 contre ligne 2, etc.
        Ideal pour deux versions successives d'un meme fichier.
        Complexite lineaire : une seule passe.
    #>
    param($Lignes1, $Lignes2)

    $resultats = New-Object 'System.Collections.Generic.List[object]'
    $max = [Math]::Max($Lignes1.Count, $Lignes2.Count)
    $nbDiff = 0

    for ($i = 0; $i -lt $max; $i++) {

        if ($MaxDifferences -gt 0 -and $nbDiff -ge $MaxDifferences) {
            Write-Etape -Message ("Arret : {0} differences atteintes" -f $MaxDifferences) -Level WARN
            break
        }

        $a = if ($i -lt $Lignes1.Count) { $Lignes1[$i] } else { $null }
        $b = if ($i -lt $Lignes2.Count) { $Lignes2[$i] } else { $null }

        if ($null -eq $a) {
            $resultats.Add((New-Difference -Statut 'AJOUTEE_DANS_2' -Ligne2 $b.Numero `
                -Valeur2 $b.Brut -Detail 'Le fichier 2 a plus de lignes'))
            $nbDiff = $nbDiff + 1
        }
        elseif ($null -eq $b) {
            $resultats.Add((New-Difference -Statut 'ABSENTE_DE_2' -Ligne1 $a.Numero `
                -Valeur1 $a.Brut -Detail 'Le fichier 1 a plus de lignes'))
            $nbDiff = $nbDiff + 1
        }
        elseif ($a.Normalise -ne $b.Normalise) {
            $resultats.Add((New-Difference -Statut 'DIFFERENTE' -Ligne1 $a.Numero -Valeur1 $a.Brut `
                -Ligne2 $b.Numero -Valeur2 $b.Brut))
            $nbDiff = $nbDiff + 1
        }
        elseif ($IncludeMatches) {
            $resultats.Add((New-Difference -Statut 'IDENTIQUE' -Ligne1 $a.Numero -Valeur1 $a.Brut `
                -Ligne2 $b.Numero -Valeur2 $b.Brut))
        }
    }

    # La virgule empeche PowerShell de "deballer" la collection :
    # sans elle, une liste vide devient $null et une liste d'1 element
    # devient un objet simple, ce qui casse .Count et l'indexation.
    return ,$resultats
}

function Compare-Ensembliste {
    <#
        Compare sans tenir compte de l'ordre : quelles valeurs sont dans A
        et pas dans B, et inversement.

        Utilise des dictionnaires (acces O(1)) : sur 100 000 x 100 000 lignes,
        une double boucle ferait 10 milliards de comparaisons ; ici on en fait
        200 000. C'est la difference entre plusieurs heures et une seconde.
    #>
    param($Lignes1, $Lignes2, [string]$Libelle1 = 'Fichier 1', [string]$Libelle2 = 'Fichier 2')

    $cmp = Get-Comparateur
    $resultats = New-Object 'System.Collections.Generic.List[object]'

    # Indexation : valeur normalisee -> liste des occurrences (numero + valeur brute)
    $index1 = New-Object 'System.Collections.Generic.Dictionary[string,object]' $cmp
    foreach ($l in $Lignes1) {
        if (-not $index1.ContainsKey($l.Normalise)) {
            $index1[$l.Normalise] = New-Object 'System.Collections.Generic.List[object]'
        }
        $index1[$l.Normalise].Add($l)
    }

    $index2 = New-Object 'System.Collections.Generic.Dictionary[string,object]' $cmp
    foreach ($l in $Lignes2) {
        if (-not $index2.ContainsKey($l.Normalise)) {
            $index2[$l.Normalise] = New-Object 'System.Collections.Generic.List[object]'
        }
        $index2[$l.Normalise].Add($l)
    }

    $nbDiff = 0

    # --- Present dans 1, absent de 2 ---
    foreach ($cle in $index1.Keys) {
        if ($MaxDifferences -gt 0 -and $nbDiff -ge $MaxDifferences) { break }

        if (-not $index2.ContainsKey($cle)) {
            foreach ($occ in $index1[$cle]) {
                $resultats.Add((New-Difference -Statut 'SEULEMENT_DANS_1' -Ligne1 $occ.Numero `
                    -Valeur1 $occ.Brut -Detail ("Absent de {0}" -f $Libelle2)))
                $nbDiff = $nbDiff + 1
            }
        }
        else {
            # Present des deux cotes : on signale les ecarts de multiplicite
            $n1 = $index1[$cle].Count
            $n2 = $index2[$cle].Count

            if ($n1 -ne $n2) {
                $resultats.Add((New-Difference -Statut 'NOMBRE_OCCURRENCES_DIFFERENT' `
                    -Ligne1 ($index1[$cle][0].Numero) -Valeur1 ($index1[$cle][0].Brut) `
                    -Ligne2 ($index2[$cle][0].Numero) -Valeur2 ($index2[$cle][0].Brut) `
                    -Detail ("{0} fois dans {1}, {2} fois dans {3}" -f $n1, $Libelle1, $n2, $Libelle2)))
                $nbDiff = $nbDiff + 1
            }
            elseif ($IncludeMatches) {
                $resultats.Add((New-Difference -Statut 'PRESENT_DANS_LES_DEUX' `
                    -Ligne1 ($index1[$cle][0].Numero) -Valeur1 ($index1[$cle][0].Brut) `
                    -Ligne2 ($index2[$cle][0].Numero) -Valeur2 ($index2[$cle][0].Brut)))
            }
        }
    }

    # --- Present dans 2, absent de 1 ---
    foreach ($cle in $index2.Keys) {
        if ($MaxDifferences -gt 0 -and $nbDiff -ge $MaxDifferences) { break }

        if (-not $index1.ContainsKey($cle)) {
            foreach ($occ in $index2[$cle]) {
                $resultats.Add((New-Difference -Statut 'SEULEMENT_DANS_2' -Ligne2 $occ.Numero `
                    -Valeur2 $occ.Brut -Detail ("Absent de {0}" -f $Libelle1)))
                $nbDiff = $nbDiff + 1
            }
        }
    }

    # La virgule empeche PowerShell de "deballer" la collection :
    # sans elle, une liste vide devient $null et une liste d'1 element
    # devient un objet simple, ce qui casse .Count et l'indexation.
    return ,$resultats
}

function Compare-ParCle {
    <#
        Rapprochement par cle metier, facon MERGE SQL :
          - lignes AJOUTEES  (cle presente seulement dans 2)
          - lignes SUPPRIMEES (cle presente seulement dans 1)
          - lignes MODIFIEES  (cle commune, valeur differente) -> une ligne
            de resultat PAR CHAMP en ecart, avec le nom de la colonne
        C'est le mode le plus precis pour un controle de migration.
    #>
    param($Source1, $Source2)

    $cmp = Get-Comparateur
    $resultats = New-Object 'System.Collections.Generic.List[object]'

    # Verification des colonnes de cle
    foreach ($k in $KeyColumns) {
        if (-not $Source1.Colonnes.Contains($k)) {
            throw ("Colonne cle '{0}' absente du fichier 1. Colonnes : {1}" -f $k, ($Source1.Colonnes -join ', '))
        }
        if (-not $Source2.Colonnes.Contains($k)) {
            throw ("Colonne cle '{0}' absente du fichier 2. Colonnes : {1}" -f $k, ($Source2.Colonnes -join ', '))
        }
    }

    # Colonnes a comparer : celles demandees, ou toutes les communes hors cles
    $colsAComparer = New-Object 'System.Collections.Generic.List[string]'
    if ($CompareColumns.Count -gt 0) {
        foreach ($c in $CompareColumns) { $colsAComparer.Add($c) }
    }
    else {
        foreach ($c in $Source1.Colonnes) {
            if ($Source2.Colonnes.Contains($c) -and ($KeyColumns -notcontains $c)) {
                $colsAComparer.Add($c)
            }
        }
    }
    Write-Etape -Message ("Colonnes comparees : {0}" -f ($colsAComparer -join ', ')) -Level DETAIL

    # Fabrique de cle composite
    function Get-CleLigne {
        param($Ligne)
        $parties = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in $KeyColumns) {
            $parties.Add((Get-ValeurNormalisee -Valeur $Ligne.Valeurs[$k]))
        }
        return ($parties -join '||')
    }

    # Indexation du fichier 1 : O(n)
    $index1 = New-Object 'System.Collections.Generic.Dictionary[string,object]' $cmp
    foreach ($l in $Source1.Lignes) {
        $cle = Get-CleLigne -Ligne $l
        if (-not $index1.ContainsKey($cle)) { $index1[$cle] = $l }
        else {
            $resultats.Add((New-Difference -Statut 'DOUBLON_DANS_1' -Ligne1 $l.Numero `
                -Cle ($cle -replace '\|\|', ' | ') -Detail 'Cle en doublon dans le fichier 1'))
        }
    }

    $clesVues = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
    $nbDiff = 0

    # Parcours du fichier 2 : O(m)
    foreach ($l2 in $Source2.Lignes) {

        if ($MaxDifferences -gt 0 -and $nbDiff -ge $MaxDifferences) { break }

        $cle = Get-CleLigne -Ligne $l2
        $cleAffichee = $cle -replace '\|\|', ' | '

        if (-not $clesVues.Add($cle)) {
            $resultats.Add((New-Difference -Statut 'DOUBLON_DANS_2' -Ligne2 $l2.Numero `
                -Cle $cleAffichee -Detail 'Cle en doublon dans le fichier 2'))
            $nbDiff = $nbDiff + 1
            continue
        }

        if (-not $index1.ContainsKey($cle)) {
            $resultats.Add((New-Difference -Statut 'AJOUTEE' -Ligne2 $l2.Numero `
                -Cle $cleAffichee -Detail 'Presente seulement dans le fichier 2'))
            $nbDiff = $nbDiff + 1
            continue
        }

        # Cle commune : comparaison champ par champ
        $l1 = $index1[$cle]
        $ecarts = 0

        foreach ($col in $colsAComparer) {
            $v1 = if ($l1.Valeurs.ContainsKey($col)) { $l1.Valeurs[$col] } else { '' }
            $v2 = if ($l2.Valeurs.ContainsKey($col)) { $l2.Valeurs[$col] } else { '' }

            if ((Get-ValeurNormalisee -Valeur $v1) -ne (Get-ValeurNormalisee -Valeur $v2)) {
                $resultats.Add((New-Difference -Statut 'MODIFIEE' -Ligne1 $l1.Numero -Valeur1 $v1 `
                    -Ligne2 $l2.Numero -Valeur2 $v2 -Cle $cleAffichee -Colonne $col))
                $ecarts = $ecarts + 1
                $nbDiff = $nbDiff + 1
            }
        }

        if ($ecarts -eq 0 -and $IncludeMatches) {
            $resultats.Add((New-Difference -Statut 'IDENTIQUE' -Ligne1 $l1.Numero -Ligne2 $l2.Numero `
                -Cle $cleAffichee))
        }
    }

    # Cles presentes dans 1 mais jamais vues dans 2
    foreach ($cle in $index1.Keys) {
        if ($MaxDifferences -gt 0 -and $nbDiff -ge $MaxDifferences) { break }
        if (-not $clesVues.Contains($cle)) {
            $resultats.Add((New-Difference -Statut 'SUPPRIMEE' -Ligne1 ($index1[$cle].Numero) `
                -Cle ($cle -replace '\|\|', ' | ') -Detail 'Presente seulement dans le fichier 1'))
            $nbDiff = $nbDiff + 1
        }
    }

    # La virgule empeche PowerShell de "deballer" la collection :
    # sans elle, une liste vide devient $null et une liste d'1 element
    # devient un objet simple, ce qui casse .Count et l'indexation.
    return ,$resultats
}


# ##############################################################################
# BLOC 4 : ECRITURE DES RESULTATS
# ##############################################################################

function Write-ResultatsCsv {
    param($Resultats, [string]$Path)

    $lignes = $Resultats | ConvertTo-Csv -NoTypeInformation -Delimiter ';'
    $texte = $lignes -join [Environment]::NewLine

    $dossier = Split-Path -Path $Path -Parent
    if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
        New-Item -Path $dossier -ItemType Directory -Force | Out-Null
    }

    # UTF8 AVEC BOM : garantit l'affichage correct des accents a l'ouverture
    # directe dans Excel (sans BOM, Excel interprete le fichier en ANSI).
    $encodage = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $texte, $encodage)
}

function Write-ResultatsTexte {
    param($Resultats, [string]$Path)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('=' * 100))
    [void]$sb.AppendLine(("RAPPORT DE COMPARAISON - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(("Fichier 1 : {0}" -f $Path1))
    [void]$sb.AppendLine(("Fichier 2 : {0}" -f $Path2))
    [void]$sb.AppendLine(('=' * 100))
    [void]$sb.AppendLine('')

    foreach ($r in $Resultats) {
        [void]$sb.AppendLine(("[{0}]" -f $r.STATUT))
        if ($r.CLE)     { [void]$sb.AppendLine(("  Cle      : {0}" -f $r.CLE)) }
        if ($r.COLONNE) { [void]$sb.AppendLine(("  Colonne  : {0}" -f $r.COLONNE)) }
        if ($r.LIGNE_1) { [void]$sb.AppendLine(("  L{0,-7} (1) : {1}" -f $r.LIGNE_1, $r.VALEUR_1)) }
        if ($r.LIGNE_2) { [void]$sb.AppendLine(("  L{0,-7} (2) : {1}" -f $r.LIGNE_2, $r.VALEUR_2)) }
        if ($r.DETAIL)  { [void]$sb.AppendLine(("  Detail   : {0}" -f $r.DETAIL)) }
        [void]$sb.AppendLine('')
    }

    $dossier = Split-Path -Path $Path -Parent
    if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
        New-Item -Path $dossier -ItemType Directory -Force | Out-Null
    }
    $encodage = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $encodage)
}

function Write-ResultatsExcel {
    <#
        Ecrit les resultats dans une feuille d'un classeur Excel.
        L'ecriture se fait CELLULE PAR CELLULE : c'est volontaire.
        L'ecriture en bloc d'un tableau 2D provoque des erreurs de marshaling
        COM (OutOfMemoryException trompeuse) selon les versions d'Excel.
        Le surcout est negligeable jusqu'a quelques dizaines de milliers de cellules.
    #>
    param($Resultats, [string]$Path, [string]$SheetName)

    $existe = Test-Path -LiteralPath $Path
    $excel = $null
    $wb = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible        = $false
        $excel.DisplayAlerts  = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents   = $false

        if ($existe) {
            $cheminComplet = (Resolve-Path -LiteralPath $Path).Path
            $wb = $excel.Workbooks.Open($cheminComplet, 0, $false)
        }
        else {
            $wb = $excel.Workbooks.Add()
            $cheminComplet = $Path
        }

        # Remplacement de la feuille homonyme
        foreach ($s in $wb.Worksheets) {
            if ($s.Name -eq $SheetName) { $s.Delete(); break }
        }

        $ws = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
        $ws.Name = $SheetName

        $entetes = @('STATUT', 'LIGNE_1', 'VALEUR_1', 'LIGNE_2', 'VALEUR_2', 'CLE', 'COLONNE', 'DETAIL')
        for ($c = 0; $c -lt $entetes.Count; $c++) {
            $ws.Cells.Item(1, $c + 1).Value2 = [string]$entetes[$c]
        }

        $total = $Resultats.Count
        $jalon = [Math]::Max([int]($total / 10), 1)

        for ($i = 0; $i -lt $total; $i++) {
            $r = $Resultats[$i]
            $lx = $i + 2

            # TOUJOURS assigner une CHAINE : l'adaptateur COM de PowerShell met
            # en cache la signature du setter Value2 au premier appel. Melanger
            # chaines et entiers (ici LIGNE_1 vaut tantot un numero, tantot '')
            # provoque une InvalidCastException. Excel reconvertit lui-meme les
            # chaines numeriques en nombres.
            $ws.Cells.Item($lx, 1).Value2 = [string]$r.STATUT
            $ws.Cells.Item($lx, 2).Value2 = [string]$r.LIGNE_1
            $ws.Cells.Item($lx, 3).Value2 = [string]$r.VALEUR_1
            $ws.Cells.Item($lx, 4).Value2 = [string]$r.LIGNE_2
            $ws.Cells.Item($lx, 5).Value2 = [string]$r.VALEUR_2
            $ws.Cells.Item($lx, 6).Value2 = [string]$r.CLE
            $ws.Cells.Item($lx, 7).Value2 = [string]$r.COLONNE
            $ws.Cells.Item($lx, 8).Value2 = [string]$r.DETAIL

            if (($i + 1) % $jalon -eq 0) {
                Write-Etape -Message ("{0}/{1} lignes ecrites" -f ($i + 1), $total) -Level DETAIL
            }
        }

        $hdr = $ws.Range('A1:H1')
        $hdr.Font.Bold = $true
        $hdr.Interior.Color = 65535
        try { $hdr.AutoFilter() | Out-Null } catch { }

        $ws.Columns.Item(1).ColumnWidth = 30
        $ws.Columns.Item(2).ColumnWidth = 10
        $ws.Columns.Item(3).ColumnWidth = 45
        $ws.Columns.Item(4).ColumnWidth = 10
        $ws.Columns.Item(5).ColumnWidth = 45
        $ws.Columns.Item(6).ColumnWidth = 30
        $ws.Columns.Item(7).ColumnWidth = 22
        $ws.Columns.Item(8).ColumnWidth = 40

        if ($existe) { $wb.Save() } else { $wb.SaveAs($cheminComplet, 51) }
    }
    finally {
        if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
        if ($excel) {
            try { $excel.ScreenUpdating = $true } catch { }
            try { $excel.EnableEvents = $true } catch { }
            try { $excel.Quit() } catch { }
        }
        foreach ($o in @($wb, $excel)) {
            if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}


# ##############################################################################
# PROGRAMME PRINCIPAL
# ##############################################################################

$etapeCourante = ''

try {
    if ($LogPath) {
        $dossierLog = Split-Path -Path $LogPath -Parent
        if ($dossierLog -and -not (Test-Path -LiteralPath $dossierLog)) {
            New-Item -Path $dossierLog -ItemType Directory -Force | Out-Null
        }
    }

    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text 'COMPARAISON DE FICHIERS / COLONNES' -Color Cyan
    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text ("Date        : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-T -Text ("PowerShell  : {0}" -f $PSVersionTable.PSVersion.ToString())
    Write-T -Text ("Fichier 1   : {0}" -f $Path1)
    Write-T -Text ("Fichier 2   : {0}" -f $Path2)
    Write-T -Text ('-' * 78) -Color DarkGray


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Verification des fichiers'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($p in @(@{ N = 'Fichier 1'; C = $Path1 }, @{ N = 'Fichier 2'; C = $Path2 })) {
        if (-not (Test-Path -LiteralPath $p.C -PathType Leaf)) {
            throw ("{0} introuvable : {1}" -f $p.N, $p.C)
        }
        $taille = (Get-Item -LiteralPath $p.C).Length
        if ($taille -eq 0) { throw ("{0} est VIDE : {1}" -f $p.N, $p.C) }
        Write-Etape -Message ("{0} : {1:N0} octets ({2})" -f $p.N, $taille, (Get-TypeFichier -Path $p.C)) -Level OK
    }

    $Path1 = (Resolve-Path -LiteralPath $Path1).Path
    $Path2 = (Resolve-Path -LiteralPath $Path2).Path

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Determination du mode de comparaison'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $type1 = Get-TypeFichier -Path $Path1
    $type2 = Get-TypeFichier -Path $Path2

    $modeEffectif = $Mode

    if ($Mode -eq 'Auto') {
        if ($Column1 -and $Column2) {
            $modeEffectif = 'Columns'
        }
        elseif ($KeyColumns.Count -gt 0) {
            $modeEffectif = 'KeyedRows'
        }
        elseif ($type1 -eq 'EXCEL' -or $type2 -eq 'EXCEL') {
            throw "Pour un fichier Excel, precisez -Column1/-Column2 (mode Columns) ou -KeyColumns (mode KeyedRows)"
        }
        else {
            $modeEffectif = 'TextPositional'
        }
        Write-Etape -Message ("Mode deduit automatiquement : {0}" -f $modeEffectif) -Level INFO
    }

    # Controles de coherence : echouer TOT avec un message clair
    if ($modeEffectif -eq 'Columns') {
        if (-not $Column1 -or -not $Column2) {
            throw "Le mode Columns necessite -Column1 ET -Column2"
        }
    }
    if ($modeEffectif -eq 'KeyedRows') {
        if ($KeyColumns.Count -eq 0) {
            throw "Le mode KeyedRows necessite -KeyColumns (ex : -KeyColumns ID)"
        }
    }
    if (($modeEffectif -eq 'TextPositional' -or $modeEffectif -eq 'TextSet')) {
        if ($type1 -eq 'EXCEL' -or $type2 -eq 'EXCEL') {
            throw ("Le mode {0} ne s'applique pas a un fichier Excel. Utilisez Columns ou KeyedRows." -f $modeEffectif)
        }
    }

    Write-Etape -Message ("Mode retenu : {0}" -f $modeEffectif) -Level OK
    Write-Etape -Message ("Options : casse {0}, trim {1}, lignes vides {2}, accents {3}" -f
        $(if ($CaseSensitive) { 'sensible' } else { 'ignoree' }),
        $(if ($NoTrim) { 'non' } else { 'oui' }),
        $(if ($IgnoreEmptyLines) { 'ignorees' } else { 'conservees' }),
        $(if ($IgnoreAccents) { 'ignores' } else { 'significatifs' })) -Level DETAIL

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Lecture des sources'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $resultats = $null

    switch ($modeEffectif) {

        'Columns' {
            # PAS de @() ici : Read-Colonne protege deja sa collection par 'return ,$X'.
            # L'envelopper a nouveau creerait un tableau a 1 element contenant TOUTE
            # la collection comme unique element, corrompant silencieusement la suite.
            $col1 = Read-Colonne -Path $Path1 -SheetName $Sheet1 -Designation $Column1 -Libelle 'Fichier 1'
            Write-Etape -Message ("Fichier 1 : {0} valeurs lues" -f $col1.Count) -Level OK

            $col2 = Read-Colonne -Path $Path2 -SheetName $Sheet2 -Designation $Column2 -Libelle 'Fichier 2'
            Write-Etape -Message ("Fichier 2 : {0} valeurs lues" -f $col2.Count) -Level OK

            Close-Etape -Name $etapeCourante -Chrono $ch

            $etapeCourante = Start-Etape -Name 'Comparaison des colonnes'
            $ch = [System.Diagnostics.Stopwatch]::StartNew()
            # Idem : Compare-Ensembliste protege deja son retour, pas de @() supplementaire.
            $resultats = Compare-Ensembliste -Lignes1 $col1 -Lignes2 $col2 `
                            -Libelle1 ("{0}!{1}" -f (Split-Path -Path $Path1 -Leaf), $Column1) `
                            -Libelle2 ("{0}!{1}" -f (Split-Path -Path $Path2 -Leaf), $Column2)
        }

        'KeyedRows' {
            $src1 = Read-LignesStructurees -Path $Path1 -SheetName $Sheet1 -Libelle 'Fichier 1'
            Write-Etape -Message ("Fichier 1 : {0} lignes, {1} colonnes" -f $src1.Lignes.Count, $src1.Colonnes.Count) -Level OK

            $src2 = Read-LignesStructurees -Path $Path2 -SheetName $Sheet2 -Libelle 'Fichier 2'
            Write-Etape -Message ("Fichier 2 : {0} lignes, {1} colonnes" -f $src2.Lignes.Count, $src2.Colonnes.Count) -Level OK

            Close-Etape -Name $etapeCourante -Chrono $ch

            $etapeCourante = Start-Etape -Name 'Rapprochement par cle'
            $ch = [System.Diagnostics.Stopwatch]::StartNew()
            $resultats = Compare-ParCle -Source1 $src1 -Source2 $src2
        }

        default {
            # TextPositional ou TextSet
            # PAS de @() : Read-LignesTexte protege deja sa collection en interne.
            $l1 = Read-LignesTexte -Path $Path1
            Write-Etape -Message ("Fichier 1 : {0} lignes lues" -f $l1.Count) -Level OK

            $l2 = Read-LignesTexte -Path $Path2
            Write-Etape -Message ("Fichier 2 : {0} lignes lues" -f $l2.Count) -Level OK

            Close-Etape -Name $etapeCourante -Chrono $ch

            $etapeCourante = Start-Etape -Name ("Comparaison {0}" -f $modeEffectif)
            $ch = [System.Diagnostics.Stopwatch]::StartNew()

            if ($modeEffectif -eq 'TextSet') {
                $resultats = Compare-Ensembliste -Lignes1 $l1 -Lignes2 $l2 `
                                -Libelle1 (Split-Path -Path $Path1 -Leaf) `
                                -Libelle2 (Split-Path -Path $Path2 -Leaf)
            }
            else {
                $resultats = Compare-Positionnel -Lignes1 $l1 -Lignes2 $l2
            }
        }
    }

    Write-Etape -Message ("{0} ligne(s) de resultat" -f $resultats.Count) -Level OK

    # Synthese par statut : donne immediatement la nature des ecarts
    $parStatut = @($resultats | Group-Object STATUT | Sort-Object Count -Descending)
    foreach ($g in $parStatut) {
        Write-Etape -Message ("{0,-32} : {1}" -f $g.Name, $g.Count) -Level DETAIL
    }

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    if ($resultats.Count -eq 0) {
        Write-T -Text ''
        Write-T -Text 'AUCUNE DIFFERENCE DETECTEE : les deux sources sont identiques.' -Color Green
    }


    # ==========================================================================
    # ECRITURE DES RESULTATS
    # ==========================================================================
    $sortiesEcrites = New-Object 'System.Collections.Generic.List[string]'

    if ($OutputPath -and $resultats.Count -gt 0) {
        $etapeCourante = Start-Etape -Name 'Ecriture du rapport'
        $ch = [System.Diagnostics.Stopwatch]::StartNew()

        $extSortie = [System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant()
        switch ($extSortie) {
            '.xlsx' {
                Write-ResultatsExcel -Resultats $resultats -Path $OutputPath -SheetName 'COMPARAISON'
            }
            '.txt' {
                Write-ResultatsTexte -Resultats $resultats -Path $OutputPath
            }
            default {
                Write-ResultatsCsv -Resultats $resultats -Path $OutputPath
            }
        }
        $sortiesEcrites.Add($OutputPath)
        Write-Etape -Message ("Ecrit : {0}" -f $OutputPath) -Level OK

        Close-Etape -Name $etapeCourante -Chrono $ch
    }

    if ($OutputSheet -and $resultats.Count -gt 0) {

        if ($type1 -ne 'EXCEL') {
            throw "-OutputSheet necessite que -Path1 soit un fichier Excel"
        }

        # Sauvegarde preventive avant toute modification
        if (-not $NoBackup) {
            $etapeCourante = Start-Etape -Name 'Sauvegarde de securite'
            $ch = [System.Diagnostics.Stopwatch]::StartNew()

            $src = Get-Item -LiteralPath $Path1
            $dossierBackup = Join-Path -Path $src.DirectoryName -ChildPath '_backup'
            if (-not (Test-Path -LiteralPath $dossierBackup)) {
                New-Item -Path $dossierBackup -ItemType Directory -Force | Out-Null
            }
            $nomBackup = "{0}_{1}{2}" -f `
                [System.IO.Path]::GetFileNameWithoutExtension($src.Name),
                (Get-Date -Format 'yyyyMMdd_HHmmss'),
                $src.Extension
            $cheminBackup = Join-Path -Path $dossierBackup -ChildPath $nomBackup
            Copy-Item -LiteralPath $Path1 -Destination $cheminBackup
            Write-Etape -Message ("Sauvegarde : {0}" -f $cheminBackup) -Level OK

            Close-Etape -Name $etapeCourante -Chrono $ch
        }

        $etapeCourante = Start-Etape -Name ("Ecriture de la feuille '{0}'" -f $OutputSheet)
        $ch = [System.Diagnostics.Stopwatch]::StartNew()

        Write-ResultatsExcel -Resultats $resultats -Path $Path1 -SheetName $OutputSheet
        $sortiesEcrites.Add(("{0} [feuille {1}]" -f $Path1, $OutputSheet))
        Write-Etape -Message ("Feuille '{0}' ecrite dans {1}" -f $OutputSheet, (Split-Path -Path $Path1 -Leaf)) -Level OK

        Close-Etape -Name $etapeCourante -Chrono $ch
    }

    if ($resultats.Count -gt 0 -and $sortiesEcrites.Count -eq 0) {
        Write-T -Text ''
        Write-T -Text 'ATTENTION : aucune sortie demandee (-OutputPath ou -OutputSheet).' -Color Yellow
        Write-T -Text 'Apercu des 20 premieres differences :' -Color Yellow
        $resultats | Select-Object -First 20 |
            Format-Table STATUT, LIGNE_1, VALEUR_1, LIGNE_2, VALEUR_2 -AutoSize |
            Out-String -Width 200 | Write-Host
    }


    # ==========================================================================
    # BILAN
    # ==========================================================================
    $duree = (Get-Date) - $script:StartTime

    Write-T -Text ('-' * 78) -Color DarkGray
    Write-T -Text 'BILAN' -Color Cyan
    Write-T -Text ("Mode              : {0}" -f $modeEffectif)
    Write-T -Text ("Lignes resultat   : {0}" -f $resultats.Count)
    foreach ($g in $parStatut) {
        $couleur = if ($g.Name -like 'IDENTIQUE*' -or $g.Name -like 'PRESENT*') { 'Green' } else { 'Yellow' }
        Write-T -Text ("  {0,-32} : {1}" -f $g.Name, $g.Count) -Color $couleur
    }
    foreach ($s in $sortiesEcrites) {
        Write-T -Text ("Sortie            : {0}" -f $s) -Color Green
    }
    Write-T -Text ("Duree             : {0:N1}s" -f $duree.TotalSeconds)
    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text 'TRAITEMENT TERMINE AVEC SUCCES' -Color Green
}
catch {
    Show-Erreur -Err $_ -Etape $etapeCourante -Contexte @{
        Path1 = $Path1
        Path2 = $Path2
        Mode  = $Mode
        Sheet1 = $Sheet1
        Sheet2 = $Sheet2
        Column1 = $Column1
        Column2 = $Column2
    }
    Write-T -Text 'TRAITEMENT INTERROMPU' -Color Red
    exit 1
}
