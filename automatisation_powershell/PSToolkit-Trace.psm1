<#
================================================================================
 PSToolkit-Trace.psm1 - Tracage, diagnostic et gestion d'exception
================================================================================

 OBJECTIF : rendre chaque bug immediatement localisable, en une seule execution.
 Quand une erreur survient, ce module affiche AUTOMATIQUEMENT :
     - le nom de l'ETAPE en cours          (ou on en etait)
     - la FONCTION en erreur                (quelle brique a casse)
     - le FICHIER et la LIGNE exacts        (ou corriger)
     - la LIGNE DE CODE fautive             (quoi corriger)
     - le TYPE .NET de l'exception          (nature du probleme)
     - la PILE D'APPEL complete             (chemin d'arrivee)
     - les VARIABLES de contexte fournies   (avec quelles donnees)

 CHARGEMENT :
     Import-Module C:\CRE\PSToolkit-Trace.psm1 -Force

 UTILISATION MINIMALE (2 lignes suffisent) :
     Start-Trace -LogPath "C:\CRE\logs\traitement.log"
     Invoke-Step -Name 'Lecture Excel' -Action { ... votre code ... }

================================================================================
#>

# ------------------------------------------------------------------------------
# Etat interne du module
# ------------------------------------------------------------------------------
$script:TraceLogPath   = $null      # fichier de log actif
$script:TraceStepStack = New-Object 'System.Collections.Generic.List[string]'
$script:TraceStepNum   = 0
$script:TraceErrors    = New-Object 'System.Collections.Generic.List[object]'
$script:TraceStart     = $null
$script:TraceVerbose   = $true


function Start-Trace {
    <#
    .SYNOPSIS
        Demarre une session de tracage.
    .DESCRIPTION
        A appeler en tout debut de script. Cree le fichier de log, remet les
        compteurs a zero et enregistre le contexte d'execution (version de
        PowerShell, machine, utilisateur) - informations indispensables quand
        on analyse un log a posteriori.
    .PARAMETER LogPath
        Chemin du fichier de log. Le dossier est cree si besoin.
        Si omis, le tracage se fait uniquement en console.
    .PARAMETER Quiet
        N'affiche rien en console (log fichier uniquement).
    .EXAMPLE
        Start-Trace -LogPath "C:\CRE\logs\extraction_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [switch]$Quiet
    )

    $script:TraceStepStack.Clear()
    $script:TraceErrors.Clear()
    $script:TraceStepNum = 0
    $script:TraceStart   = Get-Date
    $script:TraceVerbose = -not $Quiet

    if ($LogPath) {
        $dossier = Split-Path -Path $LogPath -Parent
        if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
            New-Item -Path $dossier -ItemType Directory -Force | Out-Null
        }
        $script:TraceLogPath = $LogPath
    }

    Write-TraceLine -Text ('=' * 78) -Color DarkGray
    Write-TraceLine -Text 'DEMARRAGE DU TRAITEMENT' -Color Cyan
    Write-TraceLine -Text ('=' * 78) -Color DarkGray

    # Contexte d'execution : capital pour diagnostiquer a distance
    Write-TraceLine -Text ("Date          : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-TraceLine -Text ("Machine       : {0}" -f $env:COMPUTERNAME)
    Write-TraceLine -Text ("Utilisateur   : {0}" -f $env:USERNAME)
    Write-TraceLine -Text ("PowerShell    : {0}" -f $PSVersionTable.PSVersion.ToString())
    Write-TraceLine -Text ("Edition       : {0}" -f $PSVersionTable.PSEdition)
    Write-TraceLine -Text ("Culture       : {0}" -f (Get-Culture).Name)
    if ($script:TraceLogPath) {
        Write-TraceLine -Text ("Fichier log   : {0}" -f $script:TraceLogPath)
    }
    Write-TraceLine -Text ('-' * 78) -Color DarkGray
}


function Write-TraceLine {
    <#
    .SYNOPSIS
        Ecrit une ligne brute dans le log et/ou la console (usage interne).
    .PARAMETER Text
        Texte a ecrire.
    .PARAMETER Color
        Couleur console.
    .PARAMETER NoTimestamp
        N'ajoute pas l'horodatage dans le fichier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [string]$Color = 'White',

        [switch]$NoTimestamp
    )

    if ($script:TraceVerbose) {
        Write-Host $Text -ForegroundColor $Color
    }

    if ($script:TraceLogPath) {
        $ligne = if ($NoTimestamp) {
            $Text
        } else {
            "{0} | {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
        }
        try {
            Add-Content -LiteralPath $script:TraceLogPath -Value $ligne -Encoding UTF8
        }
        catch {
            # Le log ne doit JAMAIS faire echouer le traitement principal
            Write-Host ("[log indisponible] {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
}


function Write-Step {
    <#
    .SYNOPSIS
        Journalise un message a l'interieur d'une etape.
    .DESCRIPTION
        Le message est automatiquement prefixe par le niveau d'imbrication
        et le nom de l'etape courante, ce qui permet de savoir exactement
        ou on se trouve dans le deroulement du traitement.
    .PARAMETER Message
        Texte du message.
    .PARAMETER Level
        INFO, OK, WARN, ERROR, DEBUG, DETAIL.
    .EXAMPLE
        Write-Step -Message "1250 lignes lues" -Level OK
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DEBUG', 'DETAIL')]
        [string]$Level = 'INFO'
    )

    $indentation = '  ' * $script:TraceStepStack.Count
    $symbole = switch ($Level) {
        'INFO'   { '[i]' }
        'OK'     { '[+]' }
        'WARN'   { '[!]' }
        'ERROR'  { '[X]' }
        'DEBUG'  { '[d]' }
        'DETAIL' { '   ' }
    }
    $couleur = switch ($Level) {
        'INFO'   { 'White' }
        'OK'     { 'Green' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'DEBUG'  { 'DarkGray' }
        'DETAIL' { 'Gray' }
    }

    Write-TraceLine -Text ("{0}{1} {2}" -f $indentation, $symbole, $Message) -Color $couleur
}


function Invoke-Step {
    <#
    .SYNOPSIS
        Execute un bloc de code en tant qu'ETAPE tracee et protegee.
    .DESCRIPTION
        C'est la fonction centrale du module. Elle :
          1. annonce le debut de l'etape (numerotee, indentee si imbriquee)
          2. execute le code
          3. mesure la duree
          4. en cas d'erreur, produit un RAPPORT DE DIAGNOSTIC COMPLET
             (etape, fonction, fichier, ligne, code fautif, pile d'appel)

        Les etapes peuvent etre imbriquees : l'indentation reflete la structure,
        donc en lisant le log on voit immediatement a quel niveau ca a casse.
    .PARAMETER Name
        Nom de l'etape (apparait dans le log et le rapport d'erreur).
    .PARAMETER Action
        Bloc de code a executer.
    .PARAMETER Context
        Hashtable de variables a afficher SI une erreur survient.
        Exemple : @{ Fichier = $chemin; Ligne = $i }
        C'est ce qui evite le classique "l'erreur vient d'une des 5000 lignes".
    .PARAMETER ContinueOnError
        N'interrompt pas le traitement en cas d'erreur (l'erreur est
        journalisee et collectee, puis l'execution continue).
    .OUTPUTS
        La valeur renvoyee par le bloc Action.
    .EXAMPLE
        Invoke-Step -Name 'Lecture du classeur' -Action {
            Import-ExcelSheet -Path $chemin -SheetName 'CRE'
        }
    .EXAMPLE
        # Avec contexte : en cas d'erreur, le fichier concerne sera affiche
        foreach ($f in $fichiers) {
            Invoke-Step -Name ("Traitement {0}" -f $f.Name) -ContinueOnError `
                -Context @{ Fichier = $f.FullName; Taille = $f.Length } -Action {
                    Import-Csv $f.FullName
                }
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [scriptblock]$Action,

        [hashtable]$Context = @{},

        [switch]$ContinueOnError
    )

    $script:TraceStepNum++
    $numero = $script:TraceStepNum
    $indentation = '  ' * $script:TraceStepStack.Count

    Write-TraceLine -Text ("{0}> ETAPE {1} : {2}" -f $indentation, $numero, $Name) -Color Cyan
    $script:TraceStepStack.Add($Name)

    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Execution reelle du bloc fourni
        $resultat = & $Action
        $chrono.Stop()

        Write-TraceLine -Text ("{0}< OK    {1} : {2} ({3})" -f
            $indentation, $numero, $Name, (Format-Duration -Duration $chrono.Elapsed)) -Color Green

        return $resultat
    }
    catch {
        $chrono.Stop()

        # --- RAPPORT DE DIAGNOSTIC COMPLET ---
        $rapport = Get-ErrorReport -ErrorRecord $_ -StepName $Name -Context $Context
        Show-ErrorReport -Report $rapport

        $script:TraceErrors.Add($rapport)

        if (-not $ContinueOnError) {
            # On relance : le script s'arrete, mais le diagnostic est deja affiche
            throw
        }

        Write-TraceLine -Text ("{0}< POURSUITE malgre l'erreur (etape {1})" -f $indentation, $numero) -Color Yellow
        return $null
    }
    finally {
        if ($script:TraceStepStack.Count -gt 0) {
            $script:TraceStepStack.RemoveAt($script:TraceStepStack.Count - 1)
        }
    }
}


function Get-ErrorReport {
    <#
    .SYNOPSIS
        Extrait TOUTES les informations exploitables d'une erreur PowerShell.
    .DESCRIPTION
        PowerShell dissemine les informations de diagnostic dans plusieurs
        objets imbriques. Cette fonction les rassemble en un seul objet plat,
        directement lisible ou exportable.

        Point cle : la propriete Fonction identifie la fonction reellement
        en cause, extraite de la pile d'appel - ce que le message d'erreur
        standard n'indique pas toujours.
    .PARAMETER ErrorRecord
        L'objet erreur (dans un catch : la variable $_ ).
    .PARAMETER StepName
        Nom de l'etape en cours (optionnel).
    .PARAMETER Context
        Variables de contexte a joindre au rapport.
    .EXAMPLE
        try { ... } catch { Get-ErrorReport -ErrorRecord $_ | Format-List }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$StepName = '',

        [hashtable]$Context = @{}
    )

    $info = $ErrorRecord.InvocationInfo

    # --- Identification de la fonction en cause ---
    # On cherche d'abord dans MyCommand, puis on remonte la pile d'appel.
    $fonction = ''
    if ($info -and $info.MyCommand -and $info.MyCommand.Name) {
        $fonction = $info.MyCommand.Name
    }
    if ([string]::IsNullOrWhiteSpace($fonction)) {
        # La pile a le format : "at NomFonction, C:\chemin\fichier.ps1: ligne 42"
        $pile = $ErrorRecord.ScriptStackTrace
        if ($pile) {
            $premiere = ($pile -split "`n")[0]
            $m = [regex]::Match($premiere, 'at\s+([^,]+)')
            if ($m.Success) { $fonction = $m.Groups[1].Value.Trim() }
        }
    }
    if ([string]::IsNullOrWhiteSpace($fonction)) { $fonction = '<script principal>' }

    # --- Fichier source ---
    $fichier = ''
    if ($info -and $info.ScriptName) {
        $fichier = Split-Path -Path $info.ScriptName -Leaf
    }
    if ([string]::IsNullOrWhiteSpace($fichier)) { $fichier = '<console>' }

    # --- Exceptions internes (une erreur COM ou SQL en cache souvent une autre) ---
    $chaineExceptions = New-Object 'System.Collections.Generic.List[string]'
    $ex = $ErrorRecord.Exception
    $profondeur = 0
    while ($null -ne $ex -and $profondeur -lt 5) {
        $chaineExceptions.Add(("{0} : {1}" -f $ex.GetType().FullName, $ex.Message))
        $ex = $ex.InnerException
        $profondeur++
    }

    return [PSCustomObject]@{
        Horodatage      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Etape           = $StepName
        Fonction        = $fonction
        Fichier         = $fichier
        CheminComplet   = if ($info) { $info.ScriptName } else { '' }
        Ligne           = if ($info) { $info.ScriptLineNumber } else { 0 }
        Colonne         = if ($info) { $info.OffsetInLine } else { 0 }
        CodeFautif      = if ($info -and $info.Line) { $info.Line.Trim() } else { '' }
        Message         = $ErrorRecord.Exception.Message
        TypeException   = $ErrorRecord.Exception.GetType().FullName
        CategorieErreur = $ErrorRecord.CategoryInfo.Category.ToString()
        IdErreur        = $ErrorRecord.FullyQualifiedErrorId
        ChaineExceptions = $chaineExceptions
        PileAppel       = $ErrorRecord.ScriptStackTrace
        Contexte        = $Context
    }
}


function Show-ErrorReport {
    <#
    .SYNOPSIS
        Affiche un rapport d'erreur formate et lisible.
    .DESCRIPTION
        Presentation en cadre, concue pour rester lisible sur une capture
        d'ecran : les informations essentielles (fonction, fichier, ligne,
        code fautif) sont regroupees en haut.
    .PARAMETER Report
        Rapport produit par Get-ErrorReport.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [PSObject]$Report
    )

    Write-TraceLine -Text '' -NoTimestamp
    Write-TraceLine -Text ('#' * 78) -Color Red -NoTimestamp
    Write-TraceLine -Text '#  ERREUR DETECTEE' -Color Red -NoTimestamp
    Write-TraceLine -Text ('#' * 78) -Color Red -NoTimestamp

    # --- Bloc localisation : le plus important ---
    if ($Report.Etape) {
        Write-TraceLine -Text ("#  ETAPE        : {0}" -f $Report.Etape) -Color Red -NoTimestamp
    }
    Write-TraceLine -Text ("#  FONCTION     : {0}" -f $Report.Fonction)      -Color Red -NoTimestamp
    Write-TraceLine -Text ("#  FICHIER      : {0}" -f $Report.Fichier)       -Color Red -NoTimestamp
    Write-TraceLine -Text ("#  LIGNE        : {0} (colonne {1})" -f $Report.Ligne, $Report.Colonne) -Color Red -NoTimestamp
    Write-TraceLine -Text ("#  CODE FAUTIF  : {0}" -f $Report.CodeFautif)    -Color Yellow -NoTimestamp
    Write-TraceLine -Text ('#' + ('-' * 77)) -Color Red -NoTimestamp

    # --- Bloc nature de l'erreur ---
    Write-TraceLine -Text ("#  MESSAGE      : {0}" -f $Report.Message)       -Color Red -NoTimestamp
    Write-TraceLine -Text ("#  TYPE .NET    : {0}" -f $Report.TypeException) -Color Red -NoTimestamp
    Write-TraceLine -Text ("#  CATEGORIE    : {0}" -f $Report.CategorieErreur) -Color Red -NoTimestamp

    # --- Exceptions internes (souvent la vraie cause) ---
    if ($Report.ChaineExceptions.Count -gt 1) {
        Write-TraceLine -Text ('#' + ('-' * 77)) -Color Red -NoTimestamp
        Write-TraceLine -Text '#  CHAINE D''EXCEPTIONS (la derniere est la cause racine) :' -Color Red -NoTimestamp
        $n = 0
        foreach ($e in $Report.ChaineExceptions) {
            $n++
            Write-TraceLine -Text ("#    {0}. {1}" -f $n, $e) -Color DarkYellow -NoTimestamp
        }
    }

    # --- Contexte metier : avec quelles donnees l'erreur est survenue ---
    if ($Report.Contexte -and $Report.Contexte.Count -gt 0) {
        Write-TraceLine -Text ('#' + ('-' * 77)) -Color Red -NoTimestamp
        Write-TraceLine -Text '#  CONTEXTE :' -Color Red -NoTimestamp
        foreach ($cle in $Report.Contexte.Keys) {
            $valeur = $Report.Contexte[$cle]
            $texte = if ($null -eq $valeur) { '<null>' } else { [string]$valeur }
            if ($texte.Length -gt 100) { $texte = $texte.Substring(0, 100) + '...' }
            Write-TraceLine -Text ("#    {0} = {1}" -f $cle, $texte) -Color DarkYellow -NoTimestamp
        }
    }

    # --- Pile d'appel : le chemin qui a mene a l'erreur ---
    if ($Report.PileAppel) {
        Write-TraceLine -Text ('#' + ('-' * 77)) -Color Red -NoTimestamp
        Write-TraceLine -Text '#  PILE D''APPEL :' -Color Red -NoTimestamp
        foreach ($l in ($Report.PileAppel -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($l)) {
                Write-TraceLine -Text ("#    {0}" -f $l.Trim()) -Color DarkGray -NoTimestamp
            }
        }
    }

    Write-TraceLine -Text ('#' * 78) -Color Red -NoTimestamp
    Write-TraceLine -Text '' -NoTimestamp
}


function Assert-Condition {
    <#
    .SYNOPSIS
        Verifie une condition et echoue immediatement avec un message clair.
    .DESCRIPTION
        Principe : mieux vaut echouer TOT avec un message explicite que
        tard avec une erreur incomprehensible.
        Exemple typique : verifier qu'un fichier existe AVANT de lancer
        20 minutes de traitement.
    .PARAMETER Condition
        Expression booleenne a verifier.
    .PARAMETER Message
        Message affiche si la condition est fausse.
    .PARAMETER Context
        Variables de contexte a afficher en cas d'echec.
    .EXAMPLE
        Assert-Condition -Condition (Test-Path $f) -Message "Fichier source introuvable" -Context @{ Chemin = $f }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        $Condition,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Message,

        [hashtable]$Context = @{}
    )

    $ok = $false
    if ($Condition -is [bool]) { $ok = $Condition }
    elseif ($null -ne $Condition) { $ok = [bool]$Condition }

    if (-not $ok) {
        Write-Step -Message ("ASSERTION ECHOUEE : {0}" -f $Message) -Level ERROR
        foreach ($cle in $Context.Keys) {
            Write-Step -Message ("{0} = {1}" -f $cle, $Context[$cle]) -Level DETAIL
        }
        throw ("Assertion echouee : {0}" -f $Message)
    }

    Write-Step -Message ("Verification OK : {0}" -f $Message) -Level DEBUG
}


function Format-Duration {
    <#
    .SYNOPSIS
        Met en forme une duree de facon lisible (usage interne).
    .PARAMETER Duration
        Objet TimeSpan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [TimeSpan]$Duration
    )

    if ($Duration.TotalSeconds -lt 1)      { return ("{0:N0} ms"       -f $Duration.TotalMilliseconds) }
    if ($Duration.TotalMinutes -lt 1)      { return ("{0:N1} s"        -f $Duration.TotalSeconds) }
    if ($Duration.TotalHours   -lt 1)      { return ("{0:N0} min {1:N0} s" -f $Duration.TotalMinutes, $Duration.Seconds) }
    return ("{0:N0} h {1:N0} min" -f $Duration.TotalHours, $Duration.Minutes)
}


function Stop-Trace {
    <#
    .SYNOPSIS
        Termine la session de tracage et affiche le bilan.
    .DESCRIPTION
        Affiche la duree totale, le nombre d'etapes executees et,
        surtout, le RECAPITULATIF DES ERREURS collectees : en un coup
        d'oeil on sait ce qui a echoue et ou.
    .PARAMETER ExportErrorsTo
        Chemin d'un CSV ou exporter le detail des erreurs (optionnel).
    .EXAMPLE
        Stop-Trace -ExportErrorsTo "C:\CRE\logs\erreurs.csv"
    #>
    [CmdletBinding()]
    param(
        [string]$ExportErrorsTo
    )

    $duree = if ($script:TraceStart) { (Get-Date) - $script:TraceStart } else { [TimeSpan]::Zero }

    Write-TraceLine -Text ('-' * 78) -Color DarkGray
    Write-TraceLine -Text 'BILAN DU TRAITEMENT' -Color Cyan
    Write-TraceLine -Text ("Etapes executees : {0}" -f $script:TraceStepNum)
    Write-TraceLine -Text ("Duree totale     : {0}" -f (Format-Duration -Duration $duree))

    if ($script:TraceErrors.Count -eq 0) {
        Write-TraceLine -Text 'Erreurs          : AUCUNE' -Color Green
    }
    else {
        Write-TraceLine -Text ("Erreurs          : {0}" -f $script:TraceErrors.Count) -Color Red
        Write-TraceLine -Text ('-' * 78) -Color DarkGray
        Write-TraceLine -Text 'RECAPITULATIF DES ERREURS :' -Color Red

        $n = 0
        foreach ($e in $script:TraceErrors) {
            $n++
            Write-TraceLine -Text ("  {0}. [{1}] {2}" -f $n, $e.Etape, $e.Message) -Color Red
            Write-TraceLine -Text ("     -> {0}, fonction {1}, ligne {2}" -f
                $e.Fichier, $e.Fonction, $e.Ligne) -Color DarkYellow
        }

        if ($ExportErrorsTo) {
            try {
                $script:TraceErrors |
                    Select-Object Horodatage, Etape, Fonction, Fichier, Ligne, Colonne,
                                  CodeFautif, Message, TypeException, CategorieErreur |
                    Export-Csv -LiteralPath $ExportErrorsTo -Delimiter ';' `
                               -NoTypeInformation -Encoding UTF8
                Write-TraceLine -Text ("Detail exporte : {0}" -f $ExportErrorsTo) -Color Yellow
            }
            catch {
                Write-TraceLine -Text ("Export des erreurs impossible : {0}" -f $_.Exception.Message) -Color Yellow
            }
        }
    }

    Write-TraceLine -Text ('=' * 78) -Color DarkGray

    $script:TraceLogPath = $null
}


function Get-TraceError {
    <#
    .SYNOPSIS
        Renvoie les erreurs collectees depuis le debut de la session.
    .DESCRIPTION
        Utile quand on utilise -ContinueOnError : on peut, en fin de
        traitement, analyser toutes les erreurs rencontrees.
    .EXAMPLE
        Get-TraceError | Format-Table Etape, Fonction, Ligne, Message -AutoSize
    #>
    [CmdletBinding()]
    param()
    return $script:TraceErrors
}


function Get-PowerShellInfo {
    <#
    .SYNOPSIS
        Affiche les informations de version et de capacite de PowerShell.
    .DESCRIPTION
        Indique la version, l'edition, la compatibilite des classes,
        la politique d'execution effective et les droits administrateur.
        A executer une fois sur un nouveau poste : le resultat conditionne
        ce qui est possible ou non.
    .EXAMPLE
        Get-PowerShellInfo
    #>
    [CmdletBinding()]
    param()

    $version = $PSVersionTable.PSVersion

    # Test des droits administrateur (sans les demander)
    $estAdmin = $false
    try {
        $identite = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identite)
        $estAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { }

    [PSCustomObject]@{
        Version              = $version.ToString()
        VersionMajeure       = $version.Major
        Edition              = $PSVersionTable.PSEdition
        SupporteLesClasses   = ($version.Major -ge 5)
        SupporteTernaire     = ($version.Major -ge 7)
        VersionCLR           = $PSVersionTable.CLRVersion
        Machine              = $env:COMPUTERNAME
        Utilisateur          = $env:USERNAME
        EstAdministrateur    = $estAdmin
        PolitiqueExecution   = (Get-ExecutionPolicy).ToString()
        Culture              = (Get-Culture).Name
        DossierScripts       = $PSScriptRoot
    }
}


Export-ModuleMember -Function @(
    'Start-Trace', 'Stop-Trace', 'Write-Step', 'Write-TraceLine',
    'Invoke-Step', 'Get-ErrorReport', 'Show-ErrorReport',
    'Assert-Condition', 'Format-Duration', 'Get-TraceError', 'Get-PowerShellInfo'
)
