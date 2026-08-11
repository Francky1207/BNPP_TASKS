<#
.SYNOPSIS
    Cartographie CRE -> TABLE -> COLONNES a partir de la feuille "CRE" d'un classeur Excel.

.DESCRIPTION
    Lit la feuille source (par defaut "CRE"), filtre les lignes sur TYPE_CRE = "Differentiel"
    et CRE_STATUS = "Valide" (comparaison insensible a la casse ET aux accents), puis analyse
    la colonne REQUEST (SQL) de chaque ligne pour y detecter :
      - les tables listees dans le fichier de configuration JSON,
      - pour chaque table detectee, les colonnes ciblees presentes dans la requete.

    Analyse SQL : la requete est indexee UNE SEULE FOIS par ligne (3 regex compilees) sous forme
    de HashSet / Dictionary, puis chaque table/colonne est testee par simple lookup O(1).
    Aucune regex n'est construite dans la boucle -> temps lineaire par rapport a la taille du SQL.

    Detection des colonnes, par ordre de priorite :
      1. reference qualifiee par l'alias de la table (ex : FROM KBR_ELT_NETWORKS KEN -> KEN.CONTACT_EMAIL)
      2. reference qualifiee par le nom de table (ex : KPA_PARTIES.PARTY_ID)
      3. "SELECT KEN.*" -> toutes les colonnes configurees de la table sont considerees presentes
      4. repli sur le nom nu (ex : PARTY_ID) si aucun alias n'a pu etre identifie, ou si -LooseColumns

.PARAMETER ExcelPath
    Chemin du classeur Excel a traiter (obligatoire).

.PARAMETER ConfigPath
    Chemin du JSON tables/colonnes. Par defaut : tables.json a cote du script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Extract-CreTableColumns.ps1 -ExcelPath "C:\data\CRE.xlsx"

.EXAMPLE
    .\Extract-CreTableColumns.ps1 -ExcelPath "C:\data\CRE.xlsx" -CsvPath "C:\data\mapping.csv" -KeepEmptyCre
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ExcelPath,

    # Fichier JSON { "table": ["COL1","COL2"], ... }
    [string]$ConfigPath,

    [string]$SourceSheet = 'CRE',
    [string]$TargetSheet = 'MAPPING_CRE',

    # Valeurs de filtre (accents ignores : "Differentiel" matche "Differentiel")
    [string]$TypeCre = 'Differentiel',
    [string]$Status  = 'Valide',

    # Export CSV supplementaire (le classeur est de toute facon mis a jour)
    [string]$CsvPath,

    # Conserver une ligne vide pour les CRE sans aucune table ciblee
    [switch]$KeepEmptyCre,

    # Une ligne par colonne trouvee (au lieu d'une ligne par table, colonnes concatenees)
    [switch]$OneRowPerColumn,

    # Ne repeter le nom du CRE que sur la premiere ligne du groupe
    [switch]$BlankRepeatedCre,

    # Accepter les colonnes non prefixees meme quand un alias a ete identifie (plus permissif)
    [switch]$LooseColumns,

    # N'accepter une table que si elle apparait reellement dans un FROM/JOIN (plus strict)
    [switch]$StrictTables,

    # Ignorer les tables detectees dont aucune colonne ciblee n'a ete trouvee
    [switch]$RequireColumn,

    # Ne pas ecrire dans le classeur source (utile avec -CsvPath)
    [switch]$NoExcelOutput
)

$ErrorActionPreference = 'Stop'
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ============================================================================
#  1. HELPERS
# ============================================================================

# Minuscule + suppression des accents -> comparaisons robustes ("Differentiel" == "Differentiel")
function Get-NormalizedText {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ($s.Length -eq 0) { return '' }
    $d  = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder $d.Length
    foreach ($ch in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Trim().ToLowerInvariant()
}

# ============================================================================
#  2. CONFIGURATION (tables + colonnes a rechercher)
# ============================================================================

$ExcelPath = (Resolve-Path -LiteralPath $ExcelPath).Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'tables.json' }
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Fichier de configuration introuvable : $ConfigPath"
}

$json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Ordre de declaration conserve -> ordre des lignes en sortie
$tableNames = New-Object 'System.Collections.Generic.List[string]'
$tableCols  = New-Object 'System.Collections.Generic.Dictionary[string,string[]]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $json.PSObject.Properties) {
    $name = $p.Name.Trim()
    if (-not $name) { continue }
    $tableNames.Add($name)
    $tableCols[$name] = @($p.Value | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
}
if ($tableNames.Count -eq 0) { throw "Aucune table declaree dans $ConfigPath" }

# ============================================================================
#  3. REGEX SQL (compilees une seule fois)
# ============================================================================

$rxOpt = [Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled, Singleline'

# Mots reserves qui ne peuvent JAMAIS etre un alias de table
$reserved = 'WHERE|ORDER|GROUP|HAVING|UNION|MINUS|INTERSECT|ON|AND|OR|NOT|LEFT|RIGHT|INNER|OUTER|FULL|CROSS|JOIN|SELECT|FROM|SET|VALUES|START|CONNECT|WITH|BY|PARTITION|USING|NATURAL|FOR|FETCH|OFFSET|LIMIT|AS|IN|EXISTS|CASE|WHEN|GROUPING'

# a) tous les identifiants presents dans la requete
$reWord = [regex]::new('[A-Za-z_][A-Za-z0-9_$#]*', $rxOpt)

# b) toutes les references qualifiees ALIAS.COLONNE (ou ALIAS.*)
$reQual = [regex]::new('([A-Za-z_][A-Za-z0-9_$#]*)\s*\.\s*(\*|[A-Za-z_][A-Za-z0-9_$#]*)', $rxOpt)

# c) tables declarees dans FROM / JOIN / UPDATE / INTO / ", " avec alias optionnel
$reFromTemplate = '(?:\bFROM\b|\bJOIN\b|\bUPDATE\b|\bINTO\b|,)\s*(?:(?<sch>[A-Za-z_][A-Za-z0-9_$#]*)\s*\.\s*)?(?<tbl>[A-Za-z_][A-Za-z0-9_$#]*)(?:\s+(?:AS\s+)?(?<ali>(?!(?:{0})\b)[A-Za-z_][A-Za-z0-9_$#]*))?'
$reFromPattern  = $reFromTemplate -replace '\{0\}', $reserved
$reFrom = [regex]::new($reFromPattern, $rxOpt)

# Indexe une requete SQL : mots, references qualifiees, tables/alias du FROM
function Get-SqlIndex {
    param([string]$Sql)

    $cmp   = [StringComparer]::OrdinalIgnoreCase
    $words = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
    $qual  = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]' $cmp
    $from  = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]' $cmp

    foreach ($m in $reWord.Matches($Sql))  { [void]$words.Add($m.Value) }

    foreach ($m in $reQual.Matches($Sql)) {
        $q = $m.Groups[1].Value
        $set = $null
        if (-not $qual.TryGetValue($q, [ref]$set)) {
            $set = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
            $qual[$q] = $set
        }
        [void]$set.Add($m.Groups[2].Value)
    }

    foreach ($m in $reFrom.Matches($Sql)) {
        $t = $m.Groups['tbl'].Value
        $set = $null
        if (-not $from.TryGetValue($t, [ref]$set)) {
            $set = New-Object 'System.Collections.Generic.HashSet[string]' $cmp
            $from[$t] = $set
        }
        if ($m.Groups['ali'].Success) { [void]$set.Add($m.Groups['ali'].Value) }
    }

    return [pscustomobject]@{ Words = $words; Qualified = $qual; From = $from }
}

# ============================================================================
#  4. LECTURE EXCEL (un seul aller-retour COM sur toute la plage)
# ============================================================================

$excel = $null; $wb = $null
$results = New-Object 'System.Collections.Generic.List[object]'
$creTotal = 0; $creRetenus = 0

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible        = $false
    $excel.DisplayAlerts  = $false
    $excel.ScreenUpdating = $false
    $excel.EnableEvents   = $false

    $wb = $excel.Workbooks.Open($ExcelPath, 0, $false)   # UpdateLinks=0, ReadOnly=false

    $ws = $null
    foreach ($s in $wb.Worksheets) { if ($s.Name -eq $SourceSheet) { $ws = $s; break } }
    if ($null -eq $ws) { throw "Feuille '$SourceSheet' introuvable dans $ExcelPath" }

    $ur   = $ws.UsedRange
    $data = $ur.Value2                                   # lecture en bloc = 1 appel COM
    if ($data -isnot [System.Array]) { throw "Feuille '$SourceSheet' vide." }

    $rLo = [int]$data.GetLowerBound(0); $rHi = [int]$data.GetUpperBound(0)
    $cLo = [int]$data.GetLowerBound(1); $cHi = [int]$data.GetUpperBound(1)

    # --- reperage des colonnes par leur entete (1ere ligne de la plage utilisee) ---
    $colCre = 0; $colType = 0; $colStatus = 0; $colRequest = 0
    for ($c = $cLo; $c -le $cHi; $c++) {
        switch (Get-NormalizedText $data.GetValue($rLo, $c)) {
            'cre'        { $colCre     = $c }
            'type_cre'   { $colType    = $c }
            'cre_status' { $colStatus  = $c }
            'request'    { $colRequest = $c }
        }
    }
    if ($colCre -eq 0 -or $colRequest -eq 0) {
        throw "Entetes 'CRE' et/ou 'REQUEST' introuvables sur la 1ere ligne de la feuille '$SourceSheet'."
    }

    $wantType   = Get-NormalizedText $TypeCre
    $wantStatus = Get-NormalizedText $Status

    # ============================================================================
    #  5. TRAITEMENT LIGNE PAR LIGNE
    # ============================================================================
    for ($r = $rLo + 1; $r -le $rHi; $r++) {

        $creName = [string]$data.GetValue($r, $colCre)
        if ([string]::IsNullOrWhiteSpace($creName)) { continue }
        $creName = $creName.Trim()
        $creTotal++

        # filtres TYPE_CRE / CRE_STATUS
        if ($colType   -gt 0 -and (Get-NormalizedText $data.GetValue($r, $colType))   -ne $wantType)   { continue }
        if ($colStatus -gt 0 -and (Get-NormalizedText $data.GetValue($r, $colStatus)) -ne $wantStatus) { continue }
        $creRetenus++

        $sql = [string]$data.GetValue($r, $colRequest)
        $matched = $false

        if (-not [string]::IsNullOrWhiteSpace($sql)) {
            $idx = Get-SqlIndex -Sql $sql

            foreach ($t in $tableNames) {

                # --- la table est-elle utilisee ? ---
                $aliases = $null
                $hasFrom = $idx.From.TryGetValue($t, [ref]$aliases)
                if ($StrictTables) {
                    if (-not $hasFrom) { continue }
                } elseif (-not $idx.Words.Contains($t)) { continue }

                # --- qualificateurs valides pour cette table : nom de table + alias ---
                $qualSets   = New-Object 'System.Collections.Generic.List[object]'
                $aliasCount = 0
                $star       = $false
                $probe      = New-Object 'System.Collections.Generic.List[string]'
                $probe.Add($t)
                if ($hasFrom) { foreach ($a in $aliases) { $probe.Add($a); $aliasCount++ } }

                foreach ($q in $probe) {
                    $set = $null
                    if ($idx.Qualified.TryGetValue($q, [ref]$set)) {
                        $qualSets.Add($set)
                        if ($set.Contains('*')) { $star = $true }   # SELECT KEN.* -> toutes les colonnes
                    }
                }

                # --- colonnes ciblees presentes ---
                $found = New-Object 'System.Collections.Generic.List[string]'
                foreach ($col in $tableCols[$t]) {
                    if ($star) { $found.Add($col); continue }
                    $hit = $false
                    foreach ($set in $qualSets) { if ($set.Contains($col)) { $hit = $true; break } }
                    if (-not $hit -and ($LooseColumns -or $aliasCount -eq 0)) {
                        $hit = $idx.Words.Contains($col)            # repli : colonne non prefixee
                    }
                    if ($hit) { $found.Add($col) }
                }

                if ($RequireColumn -and $found.Count -eq 0) { continue }
                $matched = $true

                if ($OneRowPerColumn -and $found.Count -gt 0) {
                    foreach ($col in $found) {
                        $results.Add([pscustomobject]@{ CRE = $creName; TABLE = $t; COLONNES = $col })
                    }
                } else {
                    $results.Add([pscustomobject]@{
                        CRE      = $creName
                        TABLE    = $t
                        COLONNES = ($found -join ', ')
                    })
                }
            }
        }

        # CRE sans aucune table ciblee -> ligne vide si demande
        if (-not $matched -and $KeepEmptyCre) {
            $results.Add([pscustomobject]@{ CRE = $creName; TABLE = ''; COLONNES = '' })
        }
    }

    # ============================================================================
    #  6. ECRITURE DES RESULTATS
    # ============================================================================
    if (-not $NoExcelOutput) {

        # suppression de l'ancienne feuille de mapping si elle existe
        foreach ($s in $wb.Worksheets) { if ($s.Name -eq $TargetSheet) { $s.Delete(); break } }

        $out = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
        $out.Name = $TargetSheet

        $n   = $results.Count
        $arr = [System.Array]::CreateInstance([object], ($n + 1), 3)
        $arr.SetValue('CRE', 0, 0); $arr.SetValue('TABLE', 0, 1); $arr.SetValue('COLONNES', 0, 2)

        $prevCre = $null
        for ($i = 0; $i -lt $n; $i++) {
            $row = $results[$i]
            $rowIdx = $i + 1
            if ($BlankRepeatedCre -and $row.CRE -eq $prevCre) { $arr.SetValue('', $rowIdx, 0) }
            else { $arr.SetValue($row.CRE, $rowIdx, 0) }
            $prevCre = $row.CRE
            $arr.SetValue($row.TABLE, $rowIdx, 1)
            $arr.SetValue($row.COLONNES, $rowIdx, 2)
        }

        # ecriture en bloc = 1 appel COM
        $rng = $out.Range($out.Cells.Item(1, 1), $out.Cells.Item($n + 1, 3))
        $rng.Value2 = $arr

        $hdr = $out.Range('A1:C1')
        $hdr.Font.Bold = $true
        $hdr.Interior.Color = 65535            # jaune
        try { $hdr.AutoFilter() | Out-Null } catch { }
        $out.Columns.Item(1).ColumnWidth = 42
        $out.Columns.Item(2).ColumnWidth = 28
        $out.Columns.Item(3).ColumnWidth = 70

        $wb.Save()
        Write-Host "Feuille '$TargetSheet' ecrite dans $ExcelPath" -ForegroundColor Green
    }

    if ($CsvPath) {
        $results | Export-Csv -LiteralPath $CsvPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
        Write-Host "CSV ecrit : $CsvPath" -ForegroundColor Green
    }

    $sw.Stop()
    Write-Host ("CRE lus : {0} | retenus ({1}/{2}) : {3} | lignes generees : {4} | duree : {5:N1}s" -f $creTotal, $TypeCre, $Status, $creRetenus, $results.Count, $sw.Elapsed.TotalSeconds)
}
catch {
    Write-Host ""
    Write-Host "========================= ERREUR =========================" -ForegroundColor Red
    Write-Host ("Message     : {0}" -f $_.Exception.Message)              -ForegroundColor Red
    Write-Host ("Ligne script: {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
    Write-Host ("Colonne     : {0}" -f $_.InvocationInfo.OffsetInLine)     -ForegroundColor Red
    Write-Host ("Instruction : {0}" -f $_.InvocationInfo.Line.Trim())     -ForegroundColor Red
    Write-Host ("Type .NET   : {0}" -f $_.Exception.GetType().FullName)   -ForegroundColor Red
    Write-Host "--- Pile d'appel ---" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    throw
}
finally {
    # ---- liberation COM systematique ----
    if ($wb)    { $wb.Close($false) | Out-Null }
    if ($excel) {
        $excel.ScreenUpdating = $true
        $excel.EnableEvents   = $true
        $excel.Quit()
    }
    foreach ($o in @($wb, $excel)) {
        if ($o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
