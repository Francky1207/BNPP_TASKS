<#
================================================================================
 Resolve-CreViewAliases.ps1
================================================================================

 OBJECTIF
 --------
 Enrichir la feuille MAPPING_CRE du classeur CRE.xlsx en y ajoutant, pour
 chaque triplet (CRE, TABLE, COLONNE), la vue SQL qui expose cette colonne
 et l'ALIAS sous lequel elle y apparait.

 CHAINE DE TRAITEMENT
 --------------------
   1. CRE.xlsx / MAPPING_CRE  -> lignes (CRE, TABLE, COLONNES)
   2. base.xlsx               -> pour CRE + "_csv" : VIEW_NAME, TABLE_TFT
   3. fichier .txt des vues   -> definitions CREATE VIEW ... AS SELECT ...
   4. Pour chaque colonne, on cherche dans la liste SELECT de chaque vue
      candidate une reference a cette colonne (ex : TFT.NAME).
      Si trouvee, on releve son alias (ex : TFT.NAME AS NOM_TIERS -> NOM_TIERS).
   5. Seules les vues OU LA COLONNE EST TROUVEE sont conservees.
   6. MAPPING_CRE est reecrite avec 5 colonnes supplementaires.

 RESULTAT DANS MAPPING_CRE
 -------------------------
   A: CRE   B: TABLE   C: COLONNES
   D: VIEW_NAME   E: TABLE_TFT   F: ALIAS   G: EXPRESSION_SOURCE   H: STATUT

 Si une colonne est trouvee dans PLUSIEURS vues, la ligne est dupliquee
 (une ligne par vue). Si elle n'est trouvee nulle part, la ligne est
 conservee avec un STATUT explicite.

 EXECUTION
 ---------
   .\Resolve-CreViewAliases.ps1 -ExcelPath "C:\CRE\CRE.xlsx" `
                                -BasePath  "C:\CRE\base.xlsx" `
                                -ViewsPath "C:\CRE\vues.txt"

 PREREQUIS : Excel installe. AUCUN droit administrateur.
================================================================================
#>

[CmdletBinding()]
param(
    # --- Fichiers d'entree ---
    [Parameter(Mandatory = $true)]
    [string]$ExcelPath,                          # CRE.xlsx (contient MAPPING_CRE)

    [Parameter(Mandatory = $true)]
    [string]$BasePath,                           # base.xlsx (CRE_csv / VIEW_NAME / TABLE_TFT)

    [Parameter(Mandatory = $true)]
    [string]$ViewsPath,                          # fichier .txt des CREATE VIEW

    # --- Noms de feuilles ---
    [string]$MappingSheet = 'MAPPING_CRE',
    [string]$BaseSheet    = '',                  # vide = detection automatique

    # --- Noms de colonnes attendus ---
    [string]$ColCre      = 'CRE',
    [string]$ColTable    = 'TABLE',
    [string]$ColColonnes = 'COLONNES',
    [string]$ColBaseCre  = 'CRE',
    [string]$ColViewName = 'VIEW_NAME',
    [string]$ColTableTft = 'TABLE_TFT',

    # --- Comportement ---
    [string]$CreSuffix = '_csv',                 # suffixe ajoute dans base.xlsx
    [switch]$NoBackup,                           # ne pas sauvegarder CRE.xlsx avant ecriture
    [switch]$NoExcelOutput,                      # ne rien ecrire dans Excel
    [string]$CsvPath,                            # export CSV supplementaire
    [string]$LogPath                             # fichier de log
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
    param(
        [string]$Text = '',
        [string]$Color = 'White'
    )
    Write-Host $Text -ForegroundColor $Color
    if ($script:LogFile) {
        try {
            $ligne = "{0} | {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
            Add-Content -LiteralPath $script:LogFile -Value $ligne -Encoding UTF8
        }
        catch { }
    }
}

function Write-Etape {
    # Message a l'interieur d'une etape, indente selon le niveau.
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
    # Note : on utilise des affectations explicites plutot que ++ / --,
    # l'operateur d'incrementation sur une variable de portee $script:
    # etant interprete differemment selon les versions de PowerShell.
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

    # Identification de la fonction reellement en cause
    $fonction = ''
    if ($info -and $info.MyCommand -and $info.MyCommand.Name) { $fonction = $info.MyCommand.Name }
    if ([string]::IsNullOrWhiteSpace($fonction) -and $Err.ScriptStackTrace) {
        $premiere = ($Err.ScriptStackTrace -split "`n")[0]
        $m = [regex]::Match($premiere, 'at\s+([^,]+)')
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
        if ($info.Line) {
            Write-T -Text ("#  CODE FAUTIF : {0}" -f $info.Line.Trim()) -Color Yellow
        }
    }
    Write-T -Text ("#  MESSAGE     : {0}" -f $Err.Exception.Message) -Color Red
    Write-T -Text ("#  TYPE .NET   : {0}" -f $Err.Exception.GetType().FullName) -Color Red

    # Exceptions internes : la cause racine est souvent la derniere
    $ex = $Err.Exception.InnerException
    $n = 0
    while ($null -ne $ex -and $n -lt 4) {
        $n++
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
# BLOC 1 : FONCTIONS UTILITAIRES
# ##############################################################################

function Get-CleNormalisee {
    <#
        Normalise une valeur pour comparaison : majuscules, sans espaces
        superflus. Utilise pour toutes les cles de rapprochement.
    #>
    param([object]$Valeur)
    if ($null -eq $Valeur) { return '' }
    return ([string]$Valeur).Trim().ToUpperInvariant()
}


function Get-ColumnIndexMap {
    <#
        Localise les colonnes d'une feuille par leur nom d'entete.
        Renvoie une hashtable NOM_MAJUSCULE -> index de colonne.
        Evite de coder en dur "colonne A, colonne B" : le script continue
        de fonctionner si l'ordre des colonnes change.
    #>
    param(
        [object]$Data,          # tableau 2D issu de UsedRange.Value2
        [int]$HeaderRow,
        [int]$ColMin,
        [int]$ColMax
    )

    $map = @{}
    for ($c = $ColMin; $c -le $ColMax; $c++) {
        $v = $Data.GetValue($HeaderRow, $c)
        if ($null -eq $v) { continue }
        $nom = Get-CleNormalisee -Valeur $v
        if ($nom -and -not $map.ContainsKey($nom)) { $map[$nom] = $c }
    }
    return $map
}


function Read-SheetData {
    <#
        Ouvre un classeur en LECTURE SEULE et renvoie le tableau 2D de la
        feuille demandee, plus ses bornes. Lecture en UN SEUL appel COM
        (UsedRange.Value2) : environ 100x plus rapide que cellule par cellule.

        Si SheetName est vide, la feuille contenant les colonnes attendues
        est recherchee automatiquement.
    #>
    param(
        [string]$Path,
        [string]$SheetName,
        [string[]]$RequiredColumns = @()
    )

    $chemin = (Resolve-Path -LiteralPath $Path).Path
    $excel = $null
    $wb = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible        = $false
        $excel.DisplayAlerts  = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents   = $false

        # ReadOnly = $true : le fichier source n'est jamais altere
        $wb = $excel.Workbooks.Open($chemin, 0, $true)

        $feuilleTrouvee = $null

        if ($SheetName) {
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $SheetName) { $feuilleTrouvee = $s; break }
            }
            if ($null -eq $feuilleTrouvee) {
                $dispo = New-Object 'System.Collections.Generic.List[string]'
                foreach ($s in $wb.Worksheets) { $dispo.Add($s.Name) }
                throw ("Feuille '{0}' introuvable dans {1}. Feuilles disponibles : {2}" -f
                       $SheetName, $Path, ($dispo -join ', '))
            }
        }
        else {
            # Detection automatique : premiere feuille contenant toutes les colonnes requises
            foreach ($s in $wb.Worksheets) {
                $ur = $s.UsedRange
                $d = $ur.Value2
                if ($d -isnot [System.Array]) { continue }

                $rMin = [int]$d.GetLowerBound(0)
                $cMin = [int]$d.GetLowerBound(1)
                $cMax = [int]$d.GetUpperBound(1)
                $map = Get-ColumnIndexMap -Data $d -HeaderRow $rMin -ColMin $cMin -ColMax $cMax

                $toutesPresentes = $true
                foreach ($rc in $RequiredColumns) {
                    if (-not $map.ContainsKey((Get-CleNormalisee -Valeur $rc))) {
                        $toutesPresentes = $false
                        break
                    }
                }
                if ($toutesPresentes) {
                    $feuilleTrouvee = $s
                    Write-Etape -Message ("Feuille detectee automatiquement : '{0}'" -f $s.Name) -Level OK
                    break
                }
            }
            if ($null -eq $feuilleTrouvee) {
                $dispo = New-Object 'System.Collections.Generic.List[string]'
                foreach ($s in $wb.Worksheets) { $dispo.Add($s.Name) }
                throw ("Aucune feuille de {0} ne contient les colonnes {1}. Feuilles : {2}" -f
                       $Path, ($RequiredColumns -join ', '), ($dispo -join ', '))
            }
        }

        $data = $feuilleTrouvee.UsedRange.Value2
        if ($data -isnot [System.Array]) {
            throw ("La feuille '{0}' de {1} est vide" -f $feuilleTrouvee.Name, $Path)
        }

        return [PSCustomObject]@{
            Data       = $data
            SheetName  = $feuilleTrouvee.Name
            RowMin     = [int]$data.GetLowerBound(0)
            RowMax     = [int]$data.GetUpperBound(0)
            ColMin     = [int]$data.GetLowerBound(1)
            ColMax     = [int]$data.GetUpperBound(1)
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


# ##############################################################################
# BLOC 2 : ANALYSE DES DEFINITIONS DE VUES SQL
# ##############################################################################

# Mots-cles SQL a ne jamais confondre avec un nom de colonne
$script:MotsClesSql = @(
    'SELECT','FROM','WHERE','AND','OR','NOT','NULL','IS','AS','ON','JOIN','INNER',
    'LEFT','RIGHT','FULL','OUTER','CROSS','GROUP','ORDER','BY','HAVING','UNION',
    'ALL','DISTINCT','TOP','CASE','WHEN','THEN','ELSE','END','CAST','CONVERT',
    'ISNULL','COALESCE','DECODE','TO_CHAR','TO_DATE','TO_NUMBER','SUBSTR','SUBSTRING',
    'NVL','COUNT','SUM','AVG','MIN','MAX','WITH','CREATE','VIEW','DBO','GO',
    'INT','VARCHAR','NVARCHAR','DATETIME','DATE','DECIMAL','NUMERIC','CHAR','BIT'
)
$script:MotsClesSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($mc in $script:MotsClesSql) { [void]$script:MotsClesSet.Add($mc) }


function Split-SelectItems {
    <#
        Decoupe la liste SELECT sur les virgules de PREMIER NIVEAU.
        Les virgules situees dans des parentheses (fonctions, sous-requetes)
        sont ignorees : DECODE(A, 1, 0) reste un seul element.
    #>
    param([string]$SelectList)

    $items = New-Object 'System.Collections.Generic.List[string]'
    $profondeur = 0
    $courant = New-Object System.Text.StringBuilder
    $dansChaine = $false

    foreach ($ch in $SelectList.ToCharArray()) {

        if ($ch -eq "'") { $dansChaine = -not $dansChaine }

        if (-not $dansChaine) {
            if ($ch -eq '(') { $profondeur++ }
            elseif ($ch -eq ')') { $profondeur-- }
            elseif ($ch -eq ',' -and $profondeur -eq 0) {
                $t = $courant.ToString().Trim()
                if ($t) { $items.Add($t) }
                [void]$courant.Clear()
                continue
            }
        }
        [void]$courant.Append($ch)
    }

    $dernier = $courant.ToString().Trim()
    if ($dernier) { $items.Add($dernier) }

    return $items
}


function Get-SelectListFromView {
    <#
        Extrait le texte compris entre le SELECT et le FROM de premier niveau.
        Les sous-requetes (SELECT ... FROM ... imbriques entre parentheses)
        sont correctement ignorees grace au suivi de la profondeur.
    #>
    param([string]$Body)

    # Recherche du premier SELECT
    $mSelect = [regex]::Match($Body, '\bSELECT\b', [System.Text.RegularExpressions.RegexOptions]'IgnoreCase')
    if (-not $mSelect.Success) { return '' }

    $debut = $mSelect.Index + $mSelect.Length
    $profondeur = 0
    $dansChaine = $false
    $i = $debut

    while ($i -lt $Body.Length) {
        $ch = $Body[$i]

        if ($ch -eq "'") { $dansChaine = -not $dansChaine }

        if (-not $dansChaine) {
            if ($ch -eq '(') { $profondeur++ }
            elseif ($ch -eq ')') { $profondeur-- }
            elseif ($profondeur -eq 0) {
                # Recherche du mot FROM isole a ce niveau
                if (($ch -eq 'F' -or $ch -eq 'f') -and ($i + 4) -le $Body.Length) {
                    $extrait = $Body.Substring($i, 4)
                    if ($extrait -match '^FROM$') {
                        $avantOk = ($i -eq 0) -or ($Body[$i - 1] -match '[\s\),]')
                        $apresOk = (($i + 4) -ge $Body.Length) -or ($Body[$i + 4] -match '[\s\(]')
                        if ($avantOk -and $apresOk) {
                            return $Body.Substring($debut, $i - $debut)
                        }
                    }
                }
            }
        }
        $i++
    }

    # Pas de FROM trouve (vue sur constantes) : on renvoie tout
    return $Body.Substring($debut)
}


function Get-ItemAliasAndColumns {
    <#
        Analyse un element de la liste SELECT et renvoie :
          - Alias    : le nom expose par la vue
          - Colonnes : les colonnes source referencees dans l'expression
          - Expression : l'expression source, sans l'alias

        Regles d'alias appliquees, dans l'ordre :
          1. "EXPR AS ALIAS"      -> ALIAS explicite
          2. "TABLE.COLONNE"      -> COLONNE (alias implicite)
          3. "COLONNE"            -> COLONNE
          4. sinon                -> vide (expression sans alias)
    #>
    param([string]$Item)

    $texte = $Item.Trim()
    $alias = ''
    $expression = $texte

    # --- 1. Alias explicite : dernier " AS " de premier niveau ---
    $profondeur = 0
    $dansChaine = $false
    $posAs = -1

    for ($i = 0; $i -lt $texte.Length - 3; $i++) {
        $ch = $texte[$i]
        if ($ch -eq "'") { $dansChaine = -not $dansChaine }
        if ($dansChaine) { continue }

        if ($ch -eq '(') { $profondeur++ }
        elseif ($ch -eq ')') { $profondeur-- }
        elseif ($profondeur -eq 0) {
            if (($ch -eq 'A' -or $ch -eq 'a') -and ($i + 2) -lt $texte.Length) {
                $suivant = $texte[$i + 1]
                if (($suivant -eq 'S' -or $suivant -eq 's')) {
                    $avantOk = ($i -eq 0) -or ($texte[$i - 1] -match '\s')
                    $apresOk = ($texte[$i + 2] -match '\s')
                    if ($avantOk -and $apresOk) { $posAs = $i }
                }
            }
        }
    }

    if ($posAs -ge 0) {
        $expression = $texte.Substring(0, $posAs).Trim()
        $alias = $texte.Substring($posAs + 3).Trim()
        # Nettoyage des crochets/guillemets eventuels : [MON_ALIAS] -> MON_ALIAS
        $alias = $alias -replace '^[\[\"`]+', ''
        $alias = $alias -replace '[\]\"`]+$', ''
        $alias = $alias.Trim()
    }
    else {
        # --- 2 et 3. Alias implicite ---
        $mQualifie = [regex]::Match($expression, '^\s*[\[\"]?(\w+)[\]\"]?\s*\.\s*[\[\"]?(\w+)[\]\"]?\s*$')
        if ($mQualifie.Success) {
            $alias = $mQualifie.Groups[2].Value
        }
        else {
            $mSimple = [regex]::Match($expression, '^\s*[\[\"]?(\w+)[\]\"]?\s*$')
            if ($mSimple.Success -and -not $script:MotsClesSet.Contains($mSimple.Groups[1].Value)) {
                $alias = $mSimple.Groups[1].Value
            }
        }
    }

    # --- Colonnes source referencees dans l'EXPRESSION (jamais dans l'alias) ---
    $colonnes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    # a) references qualifiees ALIAS.COLONNE  (cas principal : TFT.NAME)
    $rxQualifie = New-Object System.Text.RegularExpressions.Regex(
        '(\w+)\s*\.\s*(\w+)', [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')
    foreach ($m in $rxQualifie.Matches($expression)) {
        [void]$colonnes.Add($m.Groups[2].Value)
    }

    # b) identifiants nus, hors mots-cles SQL et hors chaines litterales
    $sansChaines = $expression -replace "'[^']*'", ' '
    $rxMot = New-Object System.Text.RegularExpressions.Regex(
        '\b[A-Za-z_]\w*\b', [System.Text.RegularExpressions.RegexOptions]'Compiled')
    foreach ($m in $rxMot.Matches($sansChaines)) {
        $mot = $m.Value
        if ($script:MotsClesSet.Contains($mot)) { continue }
        # On ignore le prefixe de table d'une reference qualifiee (TFT dans TFT.NAME)
        $estPrefixe = [regex]::IsMatch($sansChaines, ("\b{0}\s*\." -f [regex]::Escape($mot)))
        if ($estPrefixe) { continue }
        [void]$colonnes.Add($mot)
    }

    return [PSCustomObject]@{
        Alias      = $alias
        Colonnes   = $colonnes
        Expression = ($expression -replace '\s+', ' ').Trim()
        EstEtoile  = ($expression -match '\*')
    }
}


function Import-ViewDefinitions {
    <#
        Analyse le fichier texte contenant les CREATE VIEW et renvoie un
        dictionnaire : NOM_VUE -> liste des elements de sa liste SELECT.

        Chaque element porte son alias, son expression et l'ensemble des
        colonnes source qu'il reference.
    #>
    param([string]$Path)

    # ReadAllText gere correctement le BOM (contrairement a Get-Content -Encoding UTF8)
    $contenu = [System.IO.File]::ReadAllText($Path)
    Write-Etape -Message ("Fichier lu : {0:N0} caracteres" -f $contenu.Length) -Level DETAIL

    # Suppression des commentaires SQL pour eviter les faux positifs
    $contenu = [regex]::Replace($contenu, '/\*.*?\*/', ' ', [System.Text.RegularExpressions.RegexOptions]'Singleline')
    $contenu = [regex]::Replace($contenu, '--[^\r\n]*', ' ')

    # Reperage de tous les CREATE VIEW : [dbo].[NOM] ou dbo.NOM ou NOM
    $rxView = New-Object System.Text.RegularExpressions.Regex(
        'CREATE\s+(?:OR\s+ALTER\s+)?VIEW\s+(?:\[?(?<schema>\w+)\]?\s*\.\s*)?\[?(?<nom>\w+)\]?',
        [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')

    $correspondances = $rxView.Matches($contenu)
    Write-Etape -Message ("{0} definition(s) CREATE VIEW reperee(s)" -f $correspondances.Count) -Level INFO

    $vues = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)

    for ($i = 0; $i -lt $correspondances.Count; $i++) {

        $m = $correspondances[$i]
        $nomVue = $m.Groups['nom'].Value

        # Corps de la vue : jusqu'au prochain CREATE VIEW (ou fin de fichier)
        $debut = $m.Index + $m.Length
        $fin = if ($i + 1 -lt $correspondances.Count) { $correspondances[$i + 1].Index } else { $contenu.Length }
        $corps = $contenu.Substring($debut, $fin - $debut)

        # Extraction et decoupage de la liste SELECT
        $listeSelect = Get-SelectListFromView -Body $corps
        if ([string]::IsNullOrWhiteSpace($listeSelect)) {
            Write-Etape -Message ("Vue sans liste SELECT exploitable : {0}" -f $nomVue) -Level WARN
            continue
        }

        $items = Split-SelectItems -SelectList $listeSelect
        $analyses = New-Object 'System.Collections.Generic.List[object]'
        foreach ($it in $items) {
            $analyses.Add((Get-ItemAliasAndColumns -Item $it))
        }

        # En cas de doublon de nom de vue, la derniere definition l'emporte
        $vues[$nomVue] = $analyses
    }

    Write-Etape -Message ("{0} vue(s) analysee(s) avec succes" -f $vues.Count) -Level OK
    return $vues
}


# ##############################################################################
# PROGRAMME PRINCIPAL
# ##############################################################################

$etapeCourante = ''

try {
    # Preparation du log
    if ($LogPath) {
        $dossierLog = Split-Path -Path $LogPath -Parent
        if ($dossierLog -and -not (Test-Path -LiteralPath $dossierLog)) {
            New-Item -Path $dossierLog -ItemType Directory -Force | Out-Null
        }
    }

    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text 'RESOLUTION DES ALIAS DE VUES POUR MAPPING_CRE' -Color Cyan
    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text ("Date        : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-T -Text ("PowerShell  : {0}" -f $PSVersionTable.PSVersion.ToString())
    Write-T -Text ("CRE.xlsx    : {0}" -f $ExcelPath)
    Write-T -Text ("base.xlsx   : {0}" -f $BasePath)
    Write-T -Text ("vues .txt   : {0}" -f $ViewsPath)
    Write-T -Text ('-' * 78) -Color DarkGray


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Verification des fichiers d''entree'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($paire in @(
        @{ Nom = 'CRE.xlsx';  Chemin = $ExcelPath },
        @{ Nom = 'base.xlsx'; Chemin = $BasePath },
        @{ Nom = 'vues .txt'; Chemin = $ViewsPath }
    )) {
        if (-not (Test-Path -LiteralPath $paire.Chemin -PathType Leaf)) {
            throw ("Fichier introuvable ({0}) : {1}" -f $paire.Nom, $paire.Chemin)
        }
        $taille = (Get-Item -LiteralPath $paire.Chemin).Length
        if ($taille -eq 0) {
            throw ("Fichier VIDE ({0}) : {1}" -f $paire.Nom, $paire.Chemin)
        }
        Write-Etape -Message ("{0} : {1:N0} octets" -f $paire.Nom, $taille) -Level OK
    }

    $ExcelPath = (Resolve-Path -LiteralPath $ExcelPath).Path
    $BasePath  = (Resolve-Path -LiteralPath $BasePath).Path
    $ViewsPath = (Resolve-Path -LiteralPath $ViewsPath).Path

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Lecture de la feuille MAPPING_CRE'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $mapInfo = Read-SheetData -Path $ExcelPath -SheetName $MappingSheet
    $mapData = $mapInfo.Data

    $mapCols = Get-ColumnIndexMap -Data $mapData -HeaderRow $mapInfo.RowMin `
                                  -ColMin $mapInfo.ColMin -ColMax $mapInfo.ColMax

    foreach ($requis in @($ColCre, $ColTable, $ColColonnes)) {
        $cle = Get-CleNormalisee -Valeur $requis
        if (-not $mapCols.ContainsKey($cle)) {
            throw ("Colonne '{0}' absente de la feuille {1}. Colonnes trouvees : {2}" -f
                   $requis, $MappingSheet, (($mapCols.Keys | Sort-Object) -join ', '))
        }
    }

    $idxCre   = $mapCols[(Get-CleNormalisee -Valeur $ColCre)]
    $idxTable = $mapCols[(Get-CleNormalisee -Valeur $ColTable)]
    $idxCol   = $mapCols[(Get-CleNormalisee -Valeur $ColColonnes)]

    Write-Etape -Message ("Colonnes reperees : {0}=col{1}, {2}=col{3}, {4}=col{5}" -f
        $ColCre, $idxCre, $ColTable, $idxTable, $ColColonnes, $idxCol) -Level DETAIL

    # Chargement des lignes de mapping
    $lignesMapping = New-Object 'System.Collections.Generic.List[object]'
    $dernierCre = ''
    $dernierTable = ''

    for ($r = $mapInfo.RowMin + 1; $r -le $mapInfo.RowMax; $r++) {

        $vCre   = $mapData.GetValue($r, $idxCre)
        $vTable = $mapData.GetValue($r, $idxTable)
        $vCol   = $mapData.GetValue($r, $idxCol)

        $sCre   = if ($null -eq $vCre)   { '' } else { ([string]$vCre).Trim() }
        $sTable = if ($null -eq $vTable) { '' } else { ([string]$vTable).Trim() }
        $sCol   = if ($null -eq $vCol)   { '' } else { ([string]$vCol).Trim() }

        # Ligne entierement vide -> ignoree
        if (-not $sCre -and -not $sTable -and -not $sCol) { continue }

        # Report des valeurs precedentes si la cellule est vide (cellules fusionnees
        # ou CRE non repete d'une ligne a l'autre)
        if ($sCre)   { $dernierCre = $sCre }   else { $sCre = $dernierCre }
        if ($sTable) { $dernierTable = $sTable } else { $sTable = $dernierTable }

        $lignesMapping.Add([PSCustomObject]@{
            LigneExcel = $r
            CRE        = $sCre
            TABLE      = $sTable
            COLONNE    = $sCol
        })
    }

    Write-Etape -Message ("{0} ligne(s) de mapping chargee(s)" -f $lignesMapping.Count) -Level OK
    if ($lignesMapping.Count -eq 0) {
        throw ("La feuille {0} ne contient aucune ligne de donnees" -f $MappingSheet)
    }

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Lecture de base.xlsx (CRE -> VIEW_NAME / TABLE_TFT)'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $baseInfo = Read-SheetData -Path $BasePath -SheetName $BaseSheet `
                    -RequiredColumns @($ColBaseCre, $ColViewName, $ColTableTft)
    $baseData = $baseInfo.Data
    Write-Etape -Message ("Feuille utilisee : '{0}'" -f $baseInfo.SheetName) -Level DETAIL

    $baseCols = Get-ColumnIndexMap -Data $baseData -HeaderRow $baseInfo.RowMin `
                                   -ColMin $baseInfo.ColMin -ColMax $baseInfo.ColMax

    foreach ($requis in @($ColBaseCre, $ColViewName, $ColTableTft)) {
        $cle = Get-CleNormalisee -Valeur $requis
        if (-not $baseCols.ContainsKey($cle)) {
            throw ("Colonne '{0}' absente de base.xlsx (feuille {1}). Colonnes trouvees : {2}" -f
                   $requis, $baseInfo.SheetName, (($baseCols.Keys | Sort-Object) -join ', '))
        }
    }

    $idxBCre  = $baseCols[(Get-CleNormalisee -Valeur $ColBaseCre)]
    $idxBView = $baseCols[(Get-CleNormalisee -Valeur $ColViewName)]
    $idxBTft  = $baseCols[(Get-CleNormalisee -Valeur $ColTableTft)]

    # Index CRE normalise -> liste des couples (VIEW_NAME, TABLE_TFT).
    # Une hashtable donne un acces en O(1) : indispensable, sinon le
    # rapprochement serait quadratique.
    $indexBase = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $nbLignesBase = 0
    $vuesDejaVues = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    for ($r = $baseInfo.RowMin + 1; $r -le $baseInfo.RowMax; $r++) {

        $vCre  = $baseData.GetValue($r, $idxBCre)
        $vView = $baseData.GetValue($r, $idxBView)
        $vTft  = $baseData.GetValue($r, $idxBTft)

        $sCre  = if ($null -eq $vCre)  { '' } else { ([string]$vCre).Trim() }
        $sView = if ($null -eq $vView) { '' } else { ([string]$vView).Trim() }
        $sTft  = if ($null -eq $vTft)  { '' } else { ([string]$vTft).Trim() }

        if (-not $sCre -or -not $sView) { continue }

        $cleCre = Get-CleNormalisee -Valeur $sCre
        if (-not $indexBase.ContainsKey($cleCre)) {
            $indexBase[$cleCre] = New-Object 'System.Collections.Generic.List[object]'
        }
        $indexBase[$cleCre].Add([PSCustomObject]@{ ViewName = $sView; TableTft = $sTft })
        [void]$vuesDejaVues.Add($sView)
        $nbLignesBase++
    }

    Write-Etape -Message ("{0} ligne(s) lue(s), {1} CRE distinct(s), {2} vue(s) distincte(s)" -f
        $nbLignesBase, $indexBase.Count, $vuesDejaVues.Count) -Level OK

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Analyse des definitions de vues SQL'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $vues = Import-ViewDefinitions -Path $ViewsPath

    # Controle de couverture : les vues citees dans base.xlsx sont-elles definies ?
    $vuesManquantes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $vuesDejaVues) {
        if (-not $vues.ContainsKey($v)) { $vuesManquantes.Add($v) }
    }
    if ($vuesManquantes.Count -gt 0) {
        Write-Etape -Message ("{0} vue(s) citee(s) dans base.xlsx mais ABSENTE(S) du fichier .txt" -f
            $vuesManquantes.Count) -Level WARN
        $apercu = $vuesManquantes | Select-Object -First 5
        foreach ($v in $apercu) { Write-Etape -Message $v -Level DETAIL }
        if ($vuesManquantes.Count -gt 5) {
            Write-Etape -Message ("... et {0} autre(s)" -f ($vuesManquantes.Count - 5)) -Level DETAIL
        }
    }

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    $etapeCourante = Start-Etape -Name 'Rapprochement colonnes -> vues -> alias'
    $ch = [System.Diagnostics.Stopwatch]::StartNew()

    $resultats = New-Object 'System.Collections.Generic.List[object]'

    # Compteurs de suivi pour l'audit
    $nbTrouve = 0; $nbCreAbsent = 0; $nbAucuneVue = 0; $nbColonneVide = 0
    $creAbsents = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($ligne in $lignesMapping) {

        # --- Cas 1 : ligne sans colonne a rechercher ---
        if (-not $ligne.COLONNE) {
            $nbColonneVide++
            $resultats.Add([PSCustomObject]@{
                CRE = $ligne.CRE; TABLE = $ligne.TABLE; COLONNES = $ligne.COLONNE
                VIEW_NAME = ''; TABLE_TFT = ''; ALIAS = ''; EXPRESSION_SOURCE = ''
                STATUT = 'PAS_DE_COLONNE'
            })
            continue
        }

        # --- Recherche du CRE dans base.xlsx (avec suffixe, puis sans) ---
        $cleAvecSuffixe = Get-CleNormalisee -Valeur ("{0}{1}" -f $ligne.CRE, $CreSuffix)
        $cleSansSuffixe = Get-CleNormalisee -Valeur $ligne.CRE

        $candidats = $null
        if ($indexBase.ContainsKey($cleAvecSuffixe)) {
            $candidats = $indexBase[$cleAvecSuffixe]
        }
        elseif ($indexBase.ContainsKey($cleSansSuffixe)) {
            $candidats = $indexBase[$cleSansSuffixe]
        }

        # --- Cas 2 : CRE absent de base.xlsx ---
        if ($null -eq $candidats) {
            $nbCreAbsent++
            [void]$creAbsents.Add($ligne.CRE)
            $resultats.Add([PSCustomObject]@{
                CRE = $ligne.CRE; TABLE = $ligne.TABLE; COLONNES = $ligne.COLONNE
                VIEW_NAME = ''; TABLE_TFT = ''; ALIAS = ''; EXPRESSION_SOURCE = ''
                STATUT = 'CRE_ABSENT_DE_BASE'
            })
            continue
        }

        # --- Cas 3 : parcours des vues candidates, on ne garde que celles
        #             ou la colonne est effectivement trouvee ---
        $trouvailles = New-Object 'System.Collections.Generic.List[object]'
        $vuesTestees = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

        foreach ($cand in $candidats) {

            # Une meme vue peut apparaitre plusieurs fois dans base.xlsx
            if (-not $vuesTestees.Add($cand.ViewName)) { continue }
            if (-not $vues.ContainsKey($cand.ViewName)) { continue }

            foreach ($item in $vues[$cand.ViewName]) {
                if ($item.Colonnes.Contains($ligne.COLONNE)) {
                    $trouvailles.Add([PSCustomObject]@{
                        ViewName   = $cand.ViewName
                        TableTft   = $cand.TableTft
                        Alias      = $item.Alias
                        Expression = $item.Expression
                    })
                }
            }
        }

        if ($trouvailles.Count -eq 0) {
            # Aucune vue ne contient cette colonne
            $nbAucuneVue++
            $resultats.Add([PSCustomObject]@{
                CRE = $ligne.CRE; TABLE = $ligne.TABLE; COLONNES = $ligne.COLONNE
                VIEW_NAME = ''; TABLE_TFT = ''; ALIAS = ''; EXPRESSION_SOURCE = ''
                STATUT = 'COLONNE_NON_TROUVEE_DANS_LES_VUES'
            })
        }
        else {
            # Une ligne par vue ou la colonne a ete trouvee
            foreach ($t in $trouvailles) {
                $nbTrouve++
                $resultats.Add([PSCustomObject]@{
                    CRE = $ligne.CRE; TABLE = $ligne.TABLE; COLONNES = $ligne.COLONNE
                    VIEW_NAME = $t.ViewName
                    TABLE_TFT = $t.TableTft
                    ALIAS     = $t.Alias
                    EXPRESSION_SOURCE = $t.Expression
                    STATUT    = if ($t.Alias) { 'TROUVE' } else { 'TROUVE_SANS_ALIAS' }
                })
            }
        }
    }

    Write-Etape -Message ("Correspondances trouvees      : {0}" -f $nbTrouve) -Level OK
    Write-Etape -Message ("Colonnes non trouvees         : {0}" -f $nbAucuneVue) -Level $(if ($nbAucuneVue -gt 0) { 'WARN' } else { 'INFO' })
    Write-Etape -Message ("CRE absents de base.xlsx      : {0} ({1} CRE distincts)" -f $nbCreAbsent, $creAbsents.Count) -Level $(if ($nbCreAbsent -gt 0) { 'WARN' } else { 'INFO' })
    Write-Etape -Message ("Lignes sans colonne           : {0}" -f $nbColonneVide) -Level DETAIL
    Write-Etape -Message ("TOTAL lignes de sortie        : {0}" -f $resultats.Count) -Level INFO

    Close-Etape -Name $etapeCourante -Chrono $ch


    # ==========================================================================
    if ($CsvPath) {
        $etapeCourante = Start-Etape -Name 'Export CSV'
        $ch = [System.Diagnostics.Stopwatch]::StartNew()

        $resultats | Export-Csv -LiteralPath $CsvPath -Delimiter ';' `
                                -NoTypeInformation -Encoding UTF8
        Write-Etape -Message ("Ecrit : {0}" -f $CsvPath) -Level OK

        Close-Etape -Name $etapeCourante -Chrono $ch
    }


    # ==========================================================================
    if (-not $NoExcelOutput) {

        # --- Sauvegarde preventive ---
        if (-not $NoBackup) {
            $etapeCourante = Start-Etape -Name 'Sauvegarde de securite de CRE.xlsx'
            $ch = [System.Diagnostics.Stopwatch]::StartNew()

            $src = Get-Item -LiteralPath $ExcelPath
            $dossierBackup = Join-Path -Path $src.DirectoryName -ChildPath '_backup'
            if (-not (Test-Path -LiteralPath $dossierBackup)) {
                New-Item -Path $dossierBackup -ItemType Directory -Force | Out-Null
            }
            $nomBackup = "{0}_{1}{2}" -f
                [System.IO.Path]::GetFileNameWithoutExtension($src.Name),
                (Get-Date -Format 'yyyyMMdd_HHmmss'),
                $src.Extension
            $cheminBackup = Join-Path -Path $dossierBackup -ChildPath $nomBackup
            Copy-Item -LiteralPath $ExcelPath -Destination $cheminBackup
            Write-Etape -Message ("Sauvegarde : {0}" -f $cheminBackup) -Level OK

            Close-Etape -Name $etapeCourante -Chrono $ch
        }

        # --- Ecriture de MAPPING_CRE enrichie ---
        $etapeCourante = Start-Etape -Name 'Ecriture de la feuille MAPPING_CRE enrichie'
        $ch = [System.Diagnostics.Stopwatch]::StartNew()

        $excel = $null
        $wb = $null

        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible        = $false
            $excel.DisplayAlerts  = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents   = $false

            $wb = $excel.Workbooks.Open($ExcelPath, 0, $false)

            # Suppression de l'ancienne feuille
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $MappingSheet) { $s.Delete(); break }
            }

            $ws = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
            $ws.Name = $MappingSheet

            # En-tetes
            $entetes = @('CRE', 'TABLE', 'COLONNES', 'VIEW_NAME', 'TABLE_TFT',
                         'ALIAS', 'EXPRESSION_SOURCE', 'STATUT')
            for ($c = 0; $c -lt $entetes.Count; $c++) {
                $ws.Cells.Item(1, $c + 1).Value2 = $entetes[$c]
            }

            # Donnees, ecrites cellule par cellule.
            # C'est volontaire : l'ecriture en bloc d'un tableau 2D provoque des
            # erreurs de marshaling COM (OutOfMemoryException trompeuse) selon
            # les versions d'Excel. Le surcout est negligeable ici.
            $total = $resultats.Count
            $jalon = [Math]::Max([int]($total / 10), 1)

            for ($i = 0; $i -lt $total; $i++) {
                $row = $resultats[$i]
                $lx = $i + 2      # +1 entete, +1 index 1-based Excel

                $ws.Cells.Item($lx, 1).Value2 = $row.CRE
                $ws.Cells.Item($lx, 2).Value2 = $row.TABLE
                $ws.Cells.Item($lx, 3).Value2 = $row.COLONNES
                $ws.Cells.Item($lx, 4).Value2 = $row.VIEW_NAME
                $ws.Cells.Item($lx, 5).Value2 = $row.TABLE_TFT
                $ws.Cells.Item($lx, 6).Value2 = $row.ALIAS
                $ws.Cells.Item($lx, 7).Value2 = $row.EXPRESSION_SOURCE
                $ws.Cells.Item($lx, 8).Value2 = $row.STATUT

                if (($i + 1) % $jalon -eq 0) {
                    Write-Etape -Message ("{0}/{1} lignes ecrites" -f ($i + 1), $total) -Level DETAIL
                }
            }

            # Mise en forme de l'en-tete
            $hdr = $ws.Range('A1:H1')
            $hdr.Font.Bold = $true
            $hdr.Interior.Color = 65535
            try { $hdr.AutoFilter() | Out-Null } catch { }

            $ws.Columns.Item(1).ColumnWidth = 32
            $ws.Columns.Item(2).ColumnWidth = 26
            $ws.Columns.Item(3).ColumnWidth = 26
            $ws.Columns.Item(4).ColumnWidth = 45
            $ws.Columns.Item(5).ColumnWidth = 26
            $ws.Columns.Item(6).ColumnWidth = 32
            $ws.Columns.Item(7).ColumnWidth = 50
            $ws.Columns.Item(8).ColumnWidth = 34

            $wb.Save()
            Write-Etape -Message ("Feuille '{0}' ecrite : {1} lignes" -f $MappingSheet, $total) -Level OK
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

        Close-Etape -Name $etapeCourante -Chrono $ch
    }


    # ==========================================================================
    # BILAN
    # ==========================================================================
    $dureeTotale = (Get-Date) - $script:StartTime

    Write-T -Text ('-' * 78) -Color DarkGray
    Write-T -Text 'BILAN' -Color Cyan
    Write-T -Text ("Lignes MAPPING_CRE en entree  : {0}" -f $lignesMapping.Count)
    Write-T -Text ("Lignes produites en sortie    : {0}" -f $resultats.Count)
    Write-T -Text ("  dont correspondances OK     : {0}" -f $nbTrouve) -Color Green
    Write-T -Text ("  dont colonnes non trouvees  : {0}" -f $nbAucuneVue) -Color $(if ($nbAucuneVue -gt 0) { 'Yellow' } else { 'White' })
    Write-T -Text ("  dont CRE absents de base    : {0}" -f $nbCreAbsent) -Color $(if ($nbCreAbsent -gt 0) { 'Yellow' } else { 'White' })
    Write-T -Text ("Vues analysees                : {0}" -f $vues.Count)
    Write-T -Text ("Vues citees mais non definies : {0}" -f $vuesManquantes.Count) -Color $(if ($vuesManquantes.Count -gt 0) { 'Yellow' } else { 'White' })
    Write-T -Text ("Duree totale                  : {0:N1}s" -f $dureeTotale.TotalSeconds)
    Write-T -Text ('=' * 78) -Color DarkGray
    Write-T -Text 'TRAITEMENT TERMINE AVEC SUCCES' -Color Green
}
catch {
    Show-Erreur -Err $_ -Etape $etapeCourante -Contexte @{
        ExcelPath = $ExcelPath
        BasePath  = $BasePath
        ViewsPath = $ViewsPath
    }
    Write-T -Text 'TRAITEMENT INTERROMPU' -Color Red
    exit 1
}
