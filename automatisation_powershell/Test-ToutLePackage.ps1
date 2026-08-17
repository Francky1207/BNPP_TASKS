<#
================================================================================
 Test-ToutLePackage.ps1  -  Batterie de test complete, non interactive
================================================================================

 A QUOI CA SERT
 --------------
 Execute TOUS les scenarios de test du package en une seule fois, sans aucune
 question, et produit UN SEUL fichier de rapport consolide (succes + echecs).

 Utilisation la plus simple : double-cliquez sur Lancer-Tests.bat
 Ou en PowerShell :
     .\Test-ToutLePackage.ps1

 A la fin, ouvrez le fichier RAPPORT_TESTS_*.txt affiche a l'ecran et
 collez tout son contenu dans la conversation : c'est un texte simple,
 pas besoin de capture d'ecran.

 CE QUI EST TESTE
 ----------------
   - New-TestLab.ps1               (regeneration du laboratoire)
   - Compare-DataFiles.ps1         (les 4 modes : TextPositional, TextSet,
                                     Columns, KeyedRows)
   - Extract-CreTableColumns.ps1   (cas valide ET cas JSON invalide expres)
   - Resolve-CreViewAliases.ps1
   - 10 fonctions de PSToolkit.psm1 (CSV, qualite, doublons, recherche,
                                     fusion, encodage)

 Chaque script externe est lance dans un PROCESSUS SEPARE : si l'un
 d'eux s'arrete completement (exit), cela n'interrompt PAS la suite
 des tests. C'est essentiel pour obtenir un rapport complet meme si
 un script a un probleme.

 PREREQUIS : Excel installe. AUCUN droit administrateur.
================================================================================
#>

[CmdletBinding()]
param(
    # Dossier contenant les scripts du package (par defaut : celui de ce fichier)
    [string]$ScriptsPath = '',

    # Ne pas regenerer le laboratoire (reutilise celui deja present)
    [switch]$SkipRegenerateLab,

    # Chemin du rapport de sortie
    [string]$RapportPath = ''
)

$ErrorActionPreference = 'Stop'


# ##############################################################################
# CLASSE : resultat d'un test individuel
# ##############################################################################

class ResultatTest {
    [string] $Numero
    [string] $Nom
    [bool]   $Succes
    [double] $DureeSecondes
    [string] $Resume
    [System.Collections.Generic.List[string]] $Details

    ResultatTest([string]$numero, [string]$nom) {
        $this.Numero = $numero
        $this.Nom = $nom
        $this.Succes = $false
        $this.DureeSecondes = 0
        $this.Resume = ''
        $this.Details = New-Object 'System.Collections.Generic.List[string]'
    }
}


# ##############################################################################
# CLASSE : moteur de la batterie de test
# ##############################################################################
# Regroupe l'etat (liste des resultats, dossiers) et les methodes d'execution.
# Nommee differemment de "Journal" (utilisee par New-TestLab.ps1) pour eviter
# tout risque de collision de nom de classe au sein de la meme session PowerShell.

class MoteurTests {

    [string] $DossierScripts
    [string] $DossierLab
    [string] $ExePowerShell
    [System.Collections.Generic.List[ResultatTest]] $Resultats

    # $dossierPSHome est recu en parametre plutot que lu directement via $PSHOME :
    # les methodes de classe PowerShell n'ont PAS acces aux variables automatiques
    # de session ($PSHOME, $PSScriptRoot, $PWD...), uniquement a ce qui leur est
    # explicitement transmis. D'ou l'erreur "La variable n'est pas affectee dans
    # cette methode" si on y accede directement.
    MoteurTests([string]$dossierScripts, [string]$dossierLab, [string]$dossierPSHome) {
        $this.DossierScripts = $dossierScripts
        $this.DossierLab     = $dossierLab
        $this.Resultats      = New-Object 'System.Collections.Generic.List[ResultatTest]'

        # Chemin absolu de l'executable PowerShell courant : plus fiable que
        # de compter sur le PATH, et garantit la meme version que la session
        # en cours (5.1 ou 7+).
        $this.ExePowerShell = Join-Path $dossierPSHome 'powershell.exe'
        if (-not (Test-Path -LiteralPath $this.ExePowerShell)) {
            $this.ExePowerShell = Join-Path $dossierPSHome 'pwsh.exe'
        }
    }

    [string] Chemin([string]$sousChemin) {
        return (Join-Path $this.DossierLab $sousChemin)
    }

    [string] Script([string]$nom) {
        return (Join-Path $this.DossierScripts $nom)
    }

    # ---------------------------------------------------------------------
    # Execute un script du package DANS UN PROCESSUS SEPARE.
    # Ainsi, si le script appelle "exit" (comme le font nos scripts en cas
    # d'erreur fatale), seul CE PROCESSUS s'arrete : le harnais de test,
    # lui, continue avec le test suivant.
    # ---------------------------------------------------------------------
    [ResultatTest] ExecuterScriptExterne(
        [string]$numero, [string]$nom, [string]$nomScript,
        [hashtable]$parametres, [bool]$echecAttendu, [string[]]$motsAttendus) {

        $r = [ResultatTest]::new($numero, $nom)
        $chrono = [System.Diagnostics.Stopwatch]::StartNew()

        $cheminScript = $this.Script($nomScript)
        if (-not (Test-Path -LiteralPath $cheminScript -PathType Leaf)) {
            $r.Succes = $false
            $r.Resume = ("Script introuvable : {0}" -f $cheminScript)
            $r.Details.Add($r.Resume)
            $this.Resultats.Add($r)
            return $r
        }

        # Construction de la liste d'arguments.
        # ATTENTION : contrairement a l'operateur d'appel "&", Start-Process
        # -ArgumentList NE cite PAS automatiquement les elements contenant des
        # espaces quand on lui passe un tableau : il les rejoint simplement
        # avec un espace. Chaque VALEUR (chemin, parametre) doit donc etre
        # explicitement entouree de guillemets doubles ici, sous peine de
        # voir un chemin comme "D:\Dossier Avec Espaces\x.ps1" tronque au
        # premier espace et le reste interprete comme des arguments distincts.
        $argsList = New-Object 'System.Collections.Generic.List[string]'
        $argsList.Add('-NoProfile')
        $argsList.Add('-ExecutionPolicy'); $argsList.Add('Bypass')
        $argsList.Add('-File'); $argsList.Add('"{0}"' -f $cheminScript)

        foreach ($cle in ($parametres.Keys | Sort-Object)) {
            $v = $parametres[$cle]
            if ($v -is [bool]) {
                if ($v) { $argsList.Add(('-{0}' -f $cle)) }
            }
            elseif ($null -ne $v -and "$v" -ne '') {
                $argsList.Add(('-{0}' -f $cle))
                $argsList.Add('"{0}"' -f "$v")
            }
        }

        $r.Details.Add(('Commande : powershell.exe -File "{0}" ...' -f $nomScript))
        $r.Details.Add('')

        # Redirection VIA FICHIERS TEMPORAIRES plutot que "2>&1" sur l'operateur
        # d'appel : cette derniere convertit chaque ligne du flux d'erreur natif
        # en objet ErrorRecord PowerShell, qui devient une exception TERMINANTE
        # des lors que $ErrorActionPreference = 'Stop' est actif ici - coupant
        # la capture avant meme d'atteindre $LASTEXITCODE. Start-Process, avec
        # une redirection au niveau du systeme d'exploitation, est immunise
        # contre ce comportement, quel que soit ce que fait le script appele.
        $fichierSortie = [System.IO.Path]::GetTempFileName()
        $fichierErreur = [System.IO.Path]::GetTempFileName()

        try {
            $processus = Start-Process -FilePath $this.ExePowerShell -ArgumentList $argsList `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $fichierSortie -RedirectStandardError $fichierErreur

            $code = $processus.ExitCode

            $sortieTexte = @(Get-Content -LiteralPath $fichierSortie -ErrorAction SilentlyContinue)
            $erreurTexte = @(Get-Content -LiteralPath $fichierErreur -ErrorAction SilentlyContinue)

            foreach ($ligne in $sortieTexte) { $r.Details.Add([string]$ligne) }
            if ($erreurTexte.Count -gt 0) {
                $r.Details.Add('')
                $r.Details.Add('--- FLUX ERREUR (stderr) ---')
                foreach ($ligne in $erreurTexte) { $r.Details.Add([string]$ligne) }
            }

            $texteComplet = (($sortieTexte + $erreurTexte) -join "`n")
            $conformeAuxAttentes = $true
            foreach ($mot in $motsAttendus) {
                if ($texteComplet -notmatch [regex]::Escape($mot)) {
                    $conformeAuxAttentes = $false
                }
            }

            if ($echecAttendu) {
                # Test negatif : on VEUT que le script echoue proprement
                $r.Succes = ($code -ne 0) -and $conformeAuxAttentes
                $r.Resume = if ($r.Succes) {
                    'Echec attendu correctement detecte et signale'
                } else {
                    ("Anomalie : code sortie={0}, attendu != 0 avec diagnostic clair" -f $code)
                }
            }
            else {
                $r.Succes = ($code -eq 0) -and $conformeAuxAttentes
                $r.Resume = if ($r.Succes) {
                    'Execution reussie'
                } else {
                    ("Code de sortie={0}" -f $code)
                }
            }
        }
        catch {
            $r.Succes = $false
            $r.Resume = ("Exception du harnais : {0}" -f $_.Exception.Message)
            $r.Details.Add($r.Resume)
        }
        finally {
            Remove-Item -LiteralPath $fichierSortie, $fichierErreur -ErrorAction SilentlyContinue
        }

        $chrono.Stop()
        $r.DureeSecondes = $chrono.Elapsed.TotalSeconds
        $this.Resultats.Add($r)
        return $r
    }

    # ---------------------------------------------------------------------
    # Execute un bloc de code EN PROCESSUS (fonctions de module) : plus
    # rapide qu'un sous-processus, adapte car ces fonctions n'appellent
    # jamais "exit".
    # ---------------------------------------------------------------------
    [ResultatTest] ExecuterBlocInterne([string]$numero, [string]$nom, [scriptblock]$action) {

        $r = [ResultatTest]::new($numero, $nom)
        $chrono = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $resultat = & $action
            $r.Succes = $true
            $r.Resume = if ($resultat) { [string]$resultat } else { 'OK' }
        }
        catch {
            $r.Succes = $false
            $r.Resume = $_.Exception.Message
            $r.Details.Add(("Type .NET : {0}" -f $_.Exception.GetType().FullName))
            if ($_.InvocationInfo) {
                $r.Details.Add(("Ligne {0} : {1}" -f
                    $_.InvocationInfo.ScriptLineNumber,
                    $(if ($_.InvocationInfo.Line) { $_.InvocationInfo.Line.Trim() } else { '' })))
            }
        }

        $chrono.Stop()
        $r.DureeSecondes = $chrono.Elapsed.TotalSeconds
        $this.Resultats.Add($r)
        return $r
    }

    [void] AfficherLigne([ResultatTest]$r) {
        $symbole = if ($r.Succes) { '[OK]  ' } else { '[FAIL]' }
        $couleur = if ($r.Succes) { 'Green' } else { 'Red' }
        Write-Host ("{0} {1,-5} {2,-55} {3,6:N1}s  {4}" -f
            $symbole, $r.Numero, $r.Nom, $r.DureeSecondes, $r.Resume) -ForegroundColor $couleur
    }
}


# ##############################################################################
# PROGRAMME PRINCIPAL
# ##############################################################################

if (-not $ScriptsPath) { $ScriptsPath = $PSScriptRoot }
if (-not $ScriptsPath) { $ScriptsPath = (Get-Location).Path }

$dossierLab = Join-Path $ScriptsPath 'LAB'

if (-not $RapportPath) {
    $RapportPath = Join-Path $ScriptsPath ('RAPPORT_TESTS_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$moteur = [MoteurTests]::new($ScriptsPath, $dossierLab, $PSHOME)

Write-Host ('=' * 100) -ForegroundColor Cyan
Write-Host 'BATTERIE DE TEST COMPLETE - BOITE A OUTILS ETL' -ForegroundColor Cyan
Write-Host ('=' * 100) -ForegroundColor Cyan
Write-Host ("Scripts     : {0}" -f $ScriptsPath)
Write-Host ("Laboratoire : {0}" -f $dossierLab)
Write-Host ("PowerShell  : {0} ({1})" -f $PSVersionTable.PSVersion, $moteur.ExePowerShell)
Write-Host ('-' * 100) -ForegroundColor DarkGray


# ==============================================================================
# ETAPE 0 : regeneration du laboratoire de test
# ==============================================================================
if (-not $SkipRegenerateLab) {
    Write-Host ''
    Write-Host '--- Regeneration du laboratoire de test ---' -ForegroundColor Cyan

    $r0 = $moteur.ExecuterScriptExterne(
        '00', 'Generation du laboratoire (New-TestLab)', 'New-TestLab.ps1',
        @{ Path = $dossierLab; Force = $true },
        $false, @('LABORATOIRE PRET'))
    $moteur.AfficherLigne($r0)

    if (-not $r0.Succes) {
        Write-Host ''
        Write-Host 'Le laboratoire n''a pas pu etre genere : les tests suivants seront ignores.' -ForegroundColor Red
        Write-Host 'Consultez le rapport pour le detail de l''erreur.' -ForegroundColor Yellow
    }
}
else {
    Write-Host ''
    Write-Host '--- Laboratoire existant reutilise (-SkipRegenerateLab) ---' -ForegroundColor Yellow
}


# ==============================================================================
# SERIE A : Compare-DataFiles.ps1 - les 4 modes
# ==============================================================================
Write-Host ''
Write-Host '--- Compare-DataFiles : les 4 modes de comparaison ---' -ForegroundColor Cyan

$ra1 = $moteur.ExecuterScriptExterne(
    'A1', 'TextSet : vues.txt vs vues_v2.txt', 'Compare-DataFiles.ps1',
    @{
        Path1 = $moteur.Chemin('01_TEXTE\vues.txt')
        Path2 = $moteur.Chemin('01_TEXTE\vues_v2.txt')
        Mode = 'TextSet'
        OutputPath = $moteur.Chemin('99_SORTIES\test_A1.csv')
    },
    $false, @('TRAITEMENT TERMINE AVEC SUCCES'))
$moteur.AfficherLigne($ra1)

$ra2 = $moteur.ExecuterScriptExterne(
    'A2', 'TextPositional : liste_A.txt vs liste_B.txt', 'Compare-DataFiles.ps1',
    @{
        Path1 = $moteur.Chemin('01_TEXTE\liste_A.txt')
        Path2 = $moteur.Chemin('01_TEXTE\liste_B.txt')
        Mode = 'TextPositional'
        OutputPath = $moteur.Chemin('99_SORTIES\test_A2.csv')
    },
    $false, @('TRAITEMENT TERMINE AVEC SUCCES'))
$moteur.AfficherLigne($ra2)

$ra3 = $moteur.ExecuterScriptExterne(
    'A3', 'Columns : CRE.xlsx MAPPING_CRE vs CRE_DISTINCTS', 'Compare-DataFiles.ps1',
    @{
        Path1 = $moteur.Chemin('04_EXCEL\CRE.xlsx'); Sheet1 = 'MAPPING_CRE'; Column1 = 'CRE'
        Path2 = $moteur.Chemin('04_EXCEL\CRE.xlsx'); Sheet2 = 'CRE_DISTINCTS'; Column2 = 'CRE'
        Mode = 'Columns'
        OutputPath = $moteur.Chemin('99_SORTIES\test_A3.csv')
    },
    $false, @('TRAITEMENT TERMINE AVEC SUCCES'))
$moteur.AfficherLigne($ra3)

$ra4 = $moteur.ExecuterScriptExterne(
    'A4', 'KeyedRows : clients.csv vs clients_apres_migration.csv', 'Compare-DataFiles.ps1',
    @{
        Path1 = $moteur.Chemin('02_CSV\clients.csv')
        Path2 = $moteur.Chemin('02_CSV\clients_apres_migration.csv')
        Mode = 'KeyedRows'
        KeyColumns = 'CODE_CLIENT'
        OutputPath = $moteur.Chemin('99_SORTIES\test_A4.csv')
    },
    $false, @('TRAITEMENT TERMINE AVEC SUCCES'))
$moteur.AfficherLigne($ra4)


# ==============================================================================
# SERIE B : traitements metier CRE
# ==============================================================================
Write-Host ''
Write-Host '--- Traitements metier CRE ---' -ForegroundColor Cyan

$rb1 = $moteur.ExecuterScriptExterne(
    'B1', 'Extract-CreTableColumns (cas valide)', 'Extract-CreTableColumns.ps1',
    @{
        ExcelPath = $moteur.Chemin('04_EXCEL\CRE.xlsx')
        ConfigPath = $moteur.Chemin('03_XML_JSON\tables.json')
        CsvPath = $moteur.Chemin('99_SORTIES\test_B1.csv')
        NoExcelOutput = $true
    },
    $false, @())
$moteur.AfficherLigne($rb1)

$rb2 = $moteur.ExecuterScriptExterne(
    'B2', 'Extract-CreTableColumns (JSON invalide - echec attendu)', 'Extract-CreTableColumns.ps1',
    @{
        ExcelPath = $moteur.Chemin('04_EXCEL\CRE.xlsx')
        ConfigPath = $moteur.Chemin('03_XML_JSON\tables_INVALIDE.json')
        NoExcelOutput = $true
    },
    $true, @('JSON'))
$moteur.AfficherLigne($rb2)

$rb3 = $moteur.ExecuterScriptExterne(
    'B3', 'Resolve-CreViewAliases', 'Resolve-CreViewAliases.ps1',
    @{
        ExcelPath = $moteur.Chemin('04_EXCEL\CRE.xlsx')
        BasePath = $moteur.Chemin('04_EXCEL\base.xlsx')
        ViewsPath = $moteur.Chemin('01_TEXTE\vues.txt')
        CsvPath = $moteur.Chemin('99_SORTIES\test_B3.csv')
        NoExcelOutput = $true
    },
    $false, @('TRAITEMENT TERMINE AVEC SUCCES'))
$moteur.AfficherLigne($rb3)


# ==============================================================================
# SERIE C : fonctions du module PSToolkit (en processus, plus rapide)
# ==============================================================================
Write-Host ''
Write-Host '--- Fonctions du module PSToolkit ---' -ForegroundColor Cyan

$cheminModule = $moteur.Script('PSToolkit.psm1')
$moduleDisponible = Test-Path -LiteralPath $cheminModule -PathType Leaf

if ($moduleDisponible) {
    Import-Module $cheminModule -Force -ErrorAction Stop
}
else {
    Write-Host ('   PSToolkit.psm1 introuvable : serie C ignoree.') -ForegroundColor Yellow
}

if ($moduleDisponible) {

    $rc1 = $moteur.ExecuterBlocInterne('C1', 'Get-CsvDelimiter (ventes.csv)', {
        $sep = Get-CsvDelimiter -Path $moteur.Chemin('02_CSV\ventes.csv')
        if ($sep -ne ',') { throw ("Separateur detecte '{0}', attendu ','" -f $sep) }
        return "Separateur ',' correctement detecte"
    })
    $moteur.AfficherLigne($rc1)

    $rc2 = $moteur.ExecuterBlocInterne('C2', 'Import-CsvFast + Get-DataProfile (clients.csv)', {
        $data = Import-CsvFast -Path $moteur.Chemin('02_CSV\clients.csv')
        $profil = @($data | Get-DataProfile)
        if ($profil.Count -lt 5) { throw ("Seulement {0} colonnes profilees, attendu >= 5" -f $profil.Count) }
        return ("{0} lignes, {1} colonnes profilees" -f $data.Count, $profil.Count)
    })
    $moteur.AfficherLigne($rc2)

    $rc3 = $moteur.ExecuterBlocInterne('C3', 'Find-DuplicateRow (clients.csv, CODE_CLIENT)', {
        $data = Import-CsvFast -Path $moteur.Chemin('02_CSV\clients.csv')
        $doublons = @($data | Find-DuplicateRow -KeyColumns 'CODE_CLIENT')
        if ($doublons.Count -lt 1) { throw 'Aucun doublon detecte, CLI0007/CLI0042 attendus' }
        return ("{0} groupe(s) de doublons detecte(s)" -f $doublons.Count)
    })
    $moteur.AfficherLigne($rc3)

    $rc4 = $moteur.ExecuterBlocInterne('C4', 'ConvertTo-TypedObject (ventes.csv)', {
        $data = Import-CsvFast -Path $moteur.Chemin('02_CSV\ventes.csv')
        $type = $data | ConvertTo-TypedObject -Schema @{ QUANTITE = 'int'; PRIX_UNITAIRE = 'decimal' }
        $premier = @($type)[0]
        if ($premier.QUANTITE -isnot [int]) { throw 'QUANTITE non convertie en int' }
        return 'Typage int/decimal correct'
    })
    $moteur.AfficherLigne($rc4)

    $rc5 = $moteur.ExecuterBlocInterne('C5', 'Test-DataQuality (clients.csv)', {
        $data = Import-CsvFast -Path $moteur.Chemin('02_CSV\clients.csv')
        $violations = @($data | Test-DataQuality -Rules @{
            CODE_CLIENT = @{ Required = $true; Unique = $true }
            MONTANT     = @{ MinValue = 0 }
        })
        if ($violations.Count -eq 0) { throw 'Aucune violation detectee, des anomalies volontaires existent' }
        return ("{0} violation(s) de qualite detectee(s)" -f $violations.Count)
    })
    $moteur.AfficherLigne($rc5)

    $rc6 = $moteur.ExecuterBlocInterne('C6', 'Search-InFile (motif ORA- dans 01_TEXTE)', {
        $trouves = @(Search-InFile -Path $moteur.Chemin('01_TEXTE') -Pattern 'ORA-' -Filter '*.log' -SimpleMatch)
        if ($trouves.Count -eq 0) { throw 'Aucune occurrence trouvee, des erreurs ORA- sont attendues' }
        return ("{0} occurrence(s) trouvee(s)" -f $trouves.Count)
    })
    $moteur.AfficherLigne($rc6)

    $rc7 = $moteur.ExecuterBlocInterne('C7', 'Merge-CsvFile (02_CSV/quotidien)', {
        $sortie = $moteur.Chemin('99_SORTIES\test_C7_fusion.csv')
        Merge-CsvFile -Path $moteur.Chemin('02_CSV\quotidien') -Destination $sortie -Confirm:$false
        if (-not (Test-Path -LiteralPath $sortie)) { throw 'Fichier fusionne non cree' }
        $n = @(Import-Csv -LiteralPath $sortie -Delimiter ';').Count
        if ($n -ne 250) { throw ("{0} lignes fusionnees, 250 attendues" -f $n) }
        return '250 lignes fusionnees correctement (5 x 50)'
    })
    $moteur.AfficherLigne($rc7)

    $rc8 = $moteur.ExecuterBlocInterne('C8', 'Get-FileEncoding (export_ancien_ansi.csv)', {
        $enc = Get-FileEncoding -Path $moteur.Chemin('02_CSV\export_ancien_ansi.csv')
        if ($enc -ne 'ANSI') { throw ("Encodage detecte '{0}', 'ANSI' attendu" -f $enc) }
        return 'Encodage ANSI correctement detecte'
    })
    $moteur.AfficherLigne($rc8)

    $rc9 = $moteur.ExecuterBlocInterne('C9', 'Convert-FileEncoding (ANSI vers UTF8)', {
        $src = $moteur.Chemin('02_CSV\export_ancien_ansi.csv')
        $dst = $moteur.Chemin('99_SORTIES\test_C9_converti.csv')
        Convert-FileEncoding -Path $src -Destination $dst -To UTF8
        $enc = Get-FileEncoding -Path $dst
        if ($enc -notlike 'UTF8*') { throw ("Conversion inefficace : encodage final '{0}'" -f $enc) }
        return 'Conversion ANSI -> UTF8 reussie'
    })
    $moteur.AfficherLigne($rc9)

    $rc10 = $moteur.ExecuterBlocInterne('C10', 'ConvertTo-SafeName', {
        $sale = 'Rapport 2026/08 (final)*.xlsx'
        $propre = ConvertTo-SafeName -Name $sale
        if ($propre -match '[/\\*]') { throw ("Caracteres interdits subsistants : {0}" -f $propre) }
        return ("'{0}' -> '{1}'" -f $sale, $propre)
    })
    $moteur.AfficherLigne($rc10)
}


# ==============================================================================
# RAPPORT CONSOLIDE
# ==============================================================================
Write-Host ''
Write-Host ('=' * 100) -ForegroundColor Cyan
Write-Host 'SYNTHESE' -ForegroundColor Cyan
Write-Host ('=' * 100) -ForegroundColor Cyan

$total = $moteur.Resultats.Count
$reussis = @($moteur.Resultats | Where-Object { $_.Succes }).Count
$echecs = $total - $reussis

Write-Host ("Total   : {0}" -f $total)
Write-Host ("Reussis : {0}" -f $reussis) -ForegroundColor Green
Write-Host ("Echecs  : {0}" -f $echecs) -ForegroundColor $(if ($echecs -gt 0) { 'Red' } else { 'Green' })

if ($echecs -gt 0) {
    Write-Host ''
    Write-Host 'Tests en echec :' -ForegroundColor Red
    foreach ($r in ($moteur.Resultats | Where-Object { -not $_.Succes })) {
        Write-Host ("  {0} - {1} : {2}" -f $r.Numero, $r.Nom, $r.Resume) -ForegroundColor Red
    }
}

# --- Construction du rapport texte consolide ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine(('=' * 100))
[void]$sb.AppendLine('RAPPORT DE TEST CONSOLIDE - BOITE A OUTILS ETL')
[void]$sb.AppendLine(("Genere le {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
[void]$sb.AppendLine(("PowerShell {0}" -f $PSVersionTable.PSVersion))
[void]$sb.AppendLine(('=' * 100))
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("TOTAL : {0}   REUSSIS : {1}   ECHECS : {2}" -f $total, $reussis, $echecs))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- TABLEAU RECAPITULATIF ---')
[void]$sb.AppendLine('')
foreach ($r in $moteur.Resultats) {
    $statut = if ($r.Succes) { 'OK  ' } else { 'FAIL' }
    [void]$sb.AppendLine(('{0} {1,-5} {2,-55} {3,6:N1}s  {4}' -f $statut, $r.Numero, $r.Nom, $r.DureeSecondes, $r.Resume))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('=' * 100))
[void]$sb.AppendLine('DETAIL COMPLET DE CHAQUE TEST')
[void]$sb.AppendLine(('=' * 100))

foreach ($r in $moteur.Resultats) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('-' * 100))
    [void]$sb.AppendLine(('TEST {0} : {1}' -f $r.Numero, $r.Nom))
    [void]$sb.AppendLine(('Statut : {0}   Duree : {1:N1}s   Resume : {2}' -f
        $(if ($r.Succes) { 'REUSSI' } else { 'ECHEC' }), $r.DureeSecondes, $r.Resume))
    [void]$sb.AppendLine(('-' * 100))
    foreach ($ligne in $r.Details) {
        [void]$sb.AppendLine($ligne)
    }
}

$texteRapport = $sb.ToString()
$encodage = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($RapportPath, $texteRapport, $encodage)

Write-Host ''
Write-Host ('=' * 100) -ForegroundColor Cyan
Write-Host ("RAPPORT ECRIT : {0}" -f $RapportPath) -ForegroundColor Green
Write-Host 'Ouvrez ce fichier et collez son contenu complet dans la conversation.' -ForegroundColor Cyan
Write-Host ('=' * 100) -ForegroundColor Cyan

if ($echecs -gt 0) { exit 1 } else { exit 0 }
