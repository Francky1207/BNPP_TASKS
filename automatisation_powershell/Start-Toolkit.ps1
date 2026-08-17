<#
================================================================================
 Start-Toolkit.ps1  -  Interface interactive de la boite a outils ETL
================================================================================

 POUR DEMARRER : double-cliquez sur Lancer-Toolkit.bat
                 ou dans PowerShell :  .\Start-Toolkit.ps1

 Cette interface vous guide pas a pas : vous choisissez une tache dans un menu,
 le programme vous pose les questions necessaires, puis affiche ET la commande
 equivalente (pour l'apprendre) ET le resultat.

 AUCUNE connaissance de PowerShell n'est necessaire.
 AUCUN droit administrateur n'est necessaire.

================================================================================
#>

[CmdletBinding()]
param(
    # Dossier contenant vos fichiers de donnees. Peut etre n'importe ou.
    [string]$DataFolder = '',

    # Dossier ou ecrire les resultats
    [string]$OutputFolder = ''
)

$ErrorActionPreference = 'Stop'


# ##############################################################################
# CLASSE : contexte de l'application
# ##############################################################################
# Regroupe l'etat partage (dossiers, journal) plutot que des variables globales
# dispersees. C'est le "modele" de l'application.

class ContexteToolkit {

    [string] $DossierScripts        # ou vivent les .ps1
    [string] $DossierDonnees        # ou sont les fichiers a traiter
    [string] $DossierSorties        # ou ecrire les resultats
    [string] $DossierLogs
    [System.Collections.Generic.List[string]] $Historique

    ContexteToolkit([string]$scripts, [string]$donnees, [string]$sorties) {
        $this.DossierScripts = $scripts
        $this.DossierDonnees = $donnees
        $this.DossierSorties = $sorties
        $this.DossierLogs    = Join-Path $sorties '_logs'
        $this.Historique     = New-Object 'System.Collections.Generic.List[string]'

        foreach ($d in @($this.DossierSorties, $this.DossierLogs)) {
            if (-not (Test-Path -LiteralPath $d)) {
                New-Item -Path $d -ItemType Directory -Force | Out-Null
            }
        }
    }

    # Chemin complet d'un script du package
    [string] Script([string]$nom) {
        return (Join-Path $this.DossierScripts $nom)
    }

    # Verifie qu'un script du package est bien present
    [bool] ScriptExiste([string]$nom) {
        return (Test-Path -LiteralPath $this.Script($nom) -PathType Leaf)
    }

    # Chemin d'un fichier de sortie horodate
    [string] NouvelleSortie([string]$prefixe, [string]$extension) {
        $nom = "{0}_{1}{2}" -f $prefixe, (Get-Date -Format 'yyyyMMdd_HHmmss'), $extension
        return (Join-Path $this.DossierSorties $nom)
    }

    [string] NouveauLog([string]$prefixe) {
        $nom = "{0}_{1}.log" -f $prefixe, (Get-Date -Format 'yyyyMMdd_HHmmss')
        return (Join-Path $this.DossierLogs $nom)
    }

    [void] Memoriser([string]$commande) {
        $this.Historique.Add($commande)
    }
}


# ##############################################################################
# CLASSE : affichage console
# ##############################################################################

class Affichage {

    static [int] $Largeur = 76

    static [void] Effacer() {
        try { Clear-Host } catch { }
    }

    static [void] Cadre([string]$titre) {
        Write-Host ''
        Write-Host ('+' + ('-' * [Affichage]::Largeur) + '+') -ForegroundColor Cyan
        $t = $titre
        if ($t.Length -gt [Affichage]::Largeur - 2) {
            $t = $t.Substring(0, [Affichage]::Largeur - 5) + '...'
        }
        $reste = [Affichage]::Largeur - $t.Length - 2
        Write-Host ('| ' + $t + (' ' * $reste) + '|') -ForegroundColor Cyan
        Write-Host ('+' + ('-' * [Affichage]::Largeur) + '+') -ForegroundColor Cyan
    }

    static [void] Separateur() {
        Write-Host ('-' * ([Affichage]::Largeur + 2)) -ForegroundColor DarkGray
    }

    static [void] Titre([string]$texte) {
        Write-Host ''
        Write-Host $texte -ForegroundColor Cyan
        Write-Host ('-' * $texte.Length) -ForegroundColor DarkGray
    }

    static [void] Info([string]$texte)      { Write-Host ("   " + $texte) -ForegroundColor White }
    static [void] Ok([string]$texte)        { Write-Host ("   [OK] " + $texte) -ForegroundColor Green }
    static [void] Attention([string]$texte) { Write-Host ("   [!]  " + $texte) -ForegroundColor Yellow }
    static [void] Erreur([string]$texte)    { Write-Host ("   [X]  " + $texte) -ForegroundColor Red }
    static [void] Aide([string]$texte)      { Write-Host ("   " + $texte) -ForegroundColor DarkGray }

    # Affiche la commande PowerShell equivalente : l'utilisateur apprend en faisant
    static [void] Commande([string]$commande) {
        Write-Host ''
        Write-Host '   Commande equivalente (vous pouvez la reutiliser directement) :' -ForegroundColor DarkGray
        Write-Host ('   ' + $commande) -ForegroundColor Yellow
        Write-Host ''
    }

    static [void] Pause() {
        Write-Host ''
        Write-Host '   Appuyez sur Entree pour revenir au menu...' -ForegroundColor DarkGray
        [void](Read-Host)
    }
}


# ##############################################################################
# CLASSE : saisie assistee
# ##############################################################################
# Toutes les demandes a l'utilisateur passent par ici : validation systematique,
# valeurs par defaut, possibilite d'annuler en tapant 0.

class Saisie {

    # Demande un texte. Renvoie $null si l'utilisateur annule.
    static [string] Texte([string]$question, [string]$defaut) {
        while ($true) {
            Write-Host ''
            if ($defaut) {
                Write-Host ("   {0}" -f $question) -ForegroundColor White
                Write-Host ("   (Entree = {0}, ou 0 pour annuler)" -f $defaut) -ForegroundColor DarkGray
            }
            else {
                Write-Host ("   {0}" -f $question) -ForegroundColor White
                Write-Host '   (0 pour annuler)' -ForegroundColor DarkGray
            }
            $r = Read-Host '   >'
            if ($r -eq '0') { return $null }
            if ([string]::IsNullOrWhiteSpace($r)) {
                if ($defaut) { return $defaut }
                Write-Host '   Une valeur est necessaire.' -ForegroundColor Yellow
                continue
            }
            return $r.Trim()
        }
        # Instruction inatteignable : l'analyseur de classes PowerShell exige
        # qu'un return figure hors de la boucle, faute de quoi il refuse de
        # compiler la classe ("Le chemin de code dans son ensemble ne renvoie
        # pas necessairement une valeur").
        return $null
    }

    # Demande un chemin de fichier existant, avec verification immediate.
    static [string] Fichier([string]$question, [string]$dossierDepart) {
        while ($true) {
            $r = [Saisie]::Texte($question, '')
            if ($null -eq $r) { return $null }

            # Chemin relatif au dossier de donnees : plus court a taper
            $candidats = New-Object 'System.Collections.Generic.List[string]'
            $candidats.Add($r)
            if ($dossierDepart) {
                $candidats.Add((Join-Path $dossierDepart $r))
            }

            foreach ($c in $candidats) {
                if (Test-Path -LiteralPath $c -PathType Leaf) {
                    return (Resolve-Path -LiteralPath $c).Path
                }
            }

            Write-Host ("   Fichier introuvable : {0}" -f $r) -ForegroundColor Yellow
            Write-Host '   Astuce : glissez-deposez le fichier dans cette fenetre' -ForegroundColor DarkGray
            Write-Host '            pour coller automatiquement son chemin.' -ForegroundColor DarkGray
        }
        return $null      # inatteignable, exige par l'analyseur de classes
    }

    # Menu de choix numerote. Renvoie l'index (base 1) ou 0 si annulation.
    static [int] Choix([string]$question, [string[]]$options) {
        Write-Host ''
        Write-Host ("   {0}" -f $question) -ForegroundColor White
        for ($i = 0; $i -lt $options.Count; $i++) {
            Write-Host ("     {0}. {1}" -f ($i + 1), $options[$i]) -ForegroundColor White
        }
        Write-Host '     0. Annuler' -ForegroundColor DarkGray

        while ($true) {
            $r = Read-Host '   >'
            $n = 0
            if ([int]::TryParse($r, [ref]$n)) {
                if ($n -eq 0) { return 0 }
                if ($n -ge 1 -and $n -le $options.Count) { return $n }
            }
            Write-Host ("   Saisissez un nombre entre 0 et {0}." -f $options.Count) -ForegroundColor Yellow
        }
        return 0          # inatteignable, exige par l'analyseur de classes
    }

    static [bool] Confirmer([string]$question) {
        Write-Host ''
        Write-Host ("   {0} [O/N]" -f $question) -ForegroundColor Yellow
        while ($true) {
            $r = Read-Host '   >'
            if ($r -match '^[oOyY]') { return $true }
            if ($r -match '^[nN]')   { return $false }
            Write-Host '   Repondez par O (oui) ou N (non).' -ForegroundColor Yellow
        }
        return $false     # inatteignable, exige par l'analyseur de classes
    }

    # Liste les feuilles d'un classeur et laisse choisir : evite les fautes de frappe
    static [string] FeuilleExcel([string]$cheminClasseur, [string]$question) {

        Write-Host ''
        Write-Host '   Lecture des feuilles du classeur...' -ForegroundColor DarkGray

        $excel = $null; $wb = $null
        $feuilles = New-Object 'System.Collections.Generic.List[string]'
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($cheminClasseur, 0, $true)
            foreach ($f in $wb.Worksheets) { $feuilles.Add($f.Name) }
        }
        catch {
            Write-Host ("   Lecture impossible : {0}" -f $_.Exception.Message) -ForegroundColor Yellow
            return [Saisie]::Texte($question, '')
        }
        finally {
            if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
            if ($excel) { try { $excel.Quit() } catch { } }
            foreach ($o in @($wb, $excel)) {
                if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
            }
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }

        if ($feuilles.Count -eq 0) { return $null }
        if ($feuilles.Count -eq 1) {
            Write-Host ("   Une seule feuille : '{0}'" -f $feuilles[0]) -ForegroundColor Green
            return $feuilles[0]
        }

        $idx = [Saisie]::Choix($question, $feuilles.ToArray())
        if ($idx -eq 0) { return $null }
        return $feuilles[$idx - 1]
    }

    # Liste les colonnes d'une feuille et laisse choisir
    static [string] ColonneExcel([string]$cheminClasseur, [string]$feuille, [string]$question) {

        Write-Host ''
        Write-Host '   Lecture des colonnes...' -ForegroundColor DarkGray

        $excel = $null; $wb = $null
        $colonnes = New-Object 'System.Collections.Generic.List[string]'
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($cheminClasseur, 0, $true)

            $ws = $null
            foreach ($f in $wb.Worksheets) { if ($f.Name -eq $feuille) { $ws = $f; break } }
            if ($null -ne $ws) {
                $data = $ws.UsedRange.Value2
                if ($data -is [System.Array]) {
                    $rMin = [int]$data.GetLowerBound(0)
                    $cMin = [int]$data.GetLowerBound(1)
                    $cMax = [int]$data.GetUpperBound(1)
                    for ($c = $cMin; $c -le $cMax; $c++) {
                        $v = $data.GetValue($rMin, $c)
                        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                            $colonnes.Add(([string]$v).Trim())
                        }
                    }
                }
            }
        }
        catch {
            Write-Host ("   Lecture impossible : {0}" -f $_.Exception.Message) -ForegroundColor Yellow
            return [Saisie]::Texte($question, '')
        }
        finally {
            if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
            if ($excel) { try { $excel.Quit() } catch { } }
            foreach ($o in @($wb, $excel)) {
                if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
            }
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }

        if ($colonnes.Count -eq 0) {
            return [Saisie]::Texte($question, '')
        }

        $idx = [Saisie]::Choix($question, $colonnes.ToArray())
        if ($idx -eq 0) { return $null }
        return $colonnes[$idx - 1]
    }
}


# ##############################################################################
# CLASSE : execution d'un script du package
# ##############################################################################

class Executeur {

    [ContexteToolkit] $Contexte

    Executeur([ContexteToolkit]$contexte) {
        $this.Contexte = $contexte
    }

    # Construit une chaine de commande lisible, pour affichage et apprentissage
    [string] ConstruireCommande([string]$script, [hashtable]$parametres) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append(('.\{0}' -f $script))
        foreach ($cle in ($parametres.Keys | Sort-Object)) {
            $v = $parametres[$cle]
            if ($v -is [bool]) {
                if ($v) { [void]$sb.Append((' -{0}' -f $cle)) }
            }
            elseif ($null -ne $v -and "$v" -ne '') {
                [void]$sb.Append((' -{0} "{1}"' -f $cle, $v))
            }
        }
        return $sb.ToString()
    }

    # Lance un script du package avec les parametres fournis
    [bool] Lancer([string]$script, [hashtable]$parametres) {

        if (-not $this.Contexte.ScriptExiste($script)) {
            [Affichage]::Erreur(("Script introuvable : {0}" -f $script))
            [Affichage]::Aide(("Il doit se trouver dans : {0}" -f $this.Contexte.DossierScripts))
            return $false
        }

        $commande = $this.ConstruireCommande($script, $parametres)
        [Affichage]::Commande($commande)
        $this.Contexte.Memoriser($commande)

        [Affichage]::Separateur()

        # Construction des arguments pour l'appel par "splatting".
        # NE PAS nommer cette variable $args : c'est une variable automatique
        # reservee par PowerShell, la reutiliser provoque des comportements
        # imprevisibles selon le contexte d'appel.
        $splat = @{}
        foreach ($cle in $parametres.Keys) {
            $v = $parametres[$cle]
            if ($v -is [bool]) {
                if ($v) { $splat[$cle] = $true }
            }
            elseif ($null -ne $v -and "$v" -ne '') {
                $splat[$cle] = $v
            }
        }

        try {
            & $this.Contexte.Script($script) @splat
            [Affichage]::Separateur()
            return $true
        }
        catch {
            [Affichage]::Separateur()
            [Affichage]::Erreur('Le traitement a echoue.')
            [Affichage]::Erreur($_.Exception.Message)
            if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
                [Affichage]::Aide(("Ligne {0} de {1}" -f
                    $_.InvocationInfo.ScriptLineNumber,
                    (Split-Path -Path $_.InvocationInfo.ScriptName -Leaf)))
            }
            [Affichage]::Aide('Le detail complet figure dans le fichier de log.')
            return $false
        }
    }
}


# ##############################################################################
# ACTIONS DU MENU
# ##############################################################################

function Invoke-ComparerFichiers {
    param([ContexteToolkit]$Ctx, [Executeur]$Exec)

    [Affichage]::Cadre('COMPARER DEUX FICHIERS TEXTE OU CSV')
    [Affichage]::Aide('Trouve les lignes qui different entre deux fichiers,')
    [Affichage]::Aide('avec les numeros de ligne. Exemple : deux versions d''un export.')

    $f1 = [Saisie]::Fichier('Chemin du PREMIER fichier :', $Ctx.DossierDonnees)
    if (-not $f1) { return }
    $f2 = [Saisie]::Fichier('Chemin du DEUXIEME fichier :', $Ctx.DossierDonnees)
    if (-not $f2) { return }

    $mode = [Saisie]::Choix('Quel type de comparaison ?', @(
        'Ligne par ligne (2 versions du meme fichier)',
        'Sans tenir compte de l''ordre (2 listes a rapprocher)'
    ))
    if ($mode -eq 0) { return }
    $modeNom = if ($mode -eq 1) { 'TextPositional' } else { 'TextSet' }

    $tolerance = [Saisie]::Confirmer('Ignorer les lignes vides et les espaces multiples ?')

    $sortie = $Ctx.NouvelleSortie('comparaison', '.csv')

    $ok = $Exec.Lancer('Compare-DataFiles.ps1', @{
        Path1               = $f1
        Path2               = $f2
        Mode                = $modeNom
        OutputPath          = $sortie
        LogPath             = $Ctx.NouveauLog('comparaison')
        IgnoreEmptyLines    = $tolerance
        NormalizeWhitespace = $tolerance
    })

    if ($ok -and (Test-Path -LiteralPath $sortie)) {
        [Affichage]::Ok(("Resultat : {0}" -f $sortie))
        if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
            Invoke-Item -LiteralPath $sortie
        }
    }
    [Affichage]::Pause()
}


function Invoke-ComparerColonnes {
    param([ContexteToolkit]$Ctx, [Executeur]$Exec)

    [Affichage]::Cadre('COMPARER DEUX COLONNES EXCEL')
    [Affichage]::Aide('Repond a : "quelles valeurs de cette colonne manquent dans l''autre ?"')
    [Affichage]::Aide('Les deux colonnes peuvent etre dans le meme fichier ou non.')

    $f1 = [Saisie]::Fichier('PREMIER classeur Excel :', $Ctx.DossierDonnees)
    if (-not $f1) { return }
    $s1 = [Saisie]::FeuilleExcel($f1, 'Quelle feuille ?')
    if (-not $s1) { return }
    $c1 = [Saisie]::ColonneExcel($f1, $s1, 'Quelle colonne comparer ?')
    if (-not $c1) { return }

    $memeFichier = [Saisie]::Confirmer('La deuxieme colonne est-elle dans le MEME fichier ?')
    if ($memeFichier) {
        $f2 = $f1
    }
    else {
        $f2 = [Saisie]::Fichier('DEUXIEME classeur Excel :', $Ctx.DossierDonnees)
        if (-not $f2) { return }
    }
    $s2 = [Saisie]::FeuilleExcel($f2, 'Quelle feuille ?')
    if (-not $s2) { return }
    $c2 = [Saisie]::ColonneExcel($f2, $s2, 'Quelle colonne comparer ?')
    if (-not $c2) { return }

    $dest = [Saisie]::Choix('Ou ecrire le resultat ?', @(
        'Dans un fichier CSV separe',
        'Dans une nouvelle feuille du PREMIER classeur'
    ))
    if ($dest -eq 0) { return }

    $params = @{
        Path1   = $f1
        Sheet1  = $s1
        Column1 = $c1
        Path2   = $f2
        Sheet2  = $s2
        Column2 = $c2
        Mode    = 'Columns'
        LogPath = $Ctx.NouveauLog('colonnes')
    }

    $sortie = ''
    if ($dest -eq 1) {
        $sortie = $Ctx.NouvelleSortie('comparaison_colonnes', '.csv')
        $params['OutputPath'] = $sortie
    }
    else {
        $params['OutputSheet'] = 'COMPARAISON'
        [Affichage]::Attention('Une sauvegarde du classeur sera creee automatiquement.')
    }

    $ok = $Exec.Lancer('Compare-DataFiles.ps1', $params)

    if ($ok -and $sortie -and (Test-Path -LiteralPath $sortie)) {
        [Affichage]::Ok(("Resultat : {0}" -f $sortie))
        if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
            Invoke-Item -LiteralPath $sortie
        }
    }
    [Affichage]::Pause()
}


function Invoke-ControlerMigration {
    param([ContexteToolkit]$Ctx, [Executeur]$Exec)

    [Affichage]::Cadre('CONTROLER UNE MIGRATION (avant / apres)')
    [Affichage]::Aide('Detecte les lignes ajoutees, supprimees et MODIFIEES champ par champ.')
    [Affichage]::Aide('Necessite une colonne identifiant chaque ligne de facon unique.')

    $f1 = [Saisie]::Fichier('Fichier AVANT :', $Ctx.DossierDonnees)
    if (-not $f1) { return }
    $f2 = [Saisie]::Fichier('Fichier APRES :', $Ctx.DossierDonnees)
    if (-not $f2) { return }

    $s1 = ''
    if ([System.IO.Path]::GetExtension($f1) -match 'xls') {
        $s1 = [Saisie]::FeuilleExcel($f1, 'Feuille du fichier AVANT ?')
    }
    $s2 = ''
    if ([System.IO.Path]::GetExtension($f2) -match 'xls') {
        $s2 = [Saisie]::FeuilleExcel($f2, 'Feuille du fichier APRES ?')
    }

    $cle = [Saisie]::Texte('Nom de la colonne CLE (ex : CODE_CLIENT) :', '')
    if (-not $cle) { return }

    $sortie = $Ctx.NouvelleSortie('controle_migration', '.csv')

    $ok = $Exec.Lancer('Compare-DataFiles.ps1', @{
        Path1      = $f1
        Path2      = $f2
        Sheet1     = $s1
        Sheet2     = $s2
        Mode       = 'KeyedRows'
        KeyColumns = $cle
        OutputPath = $sortie
        LogPath    = $Ctx.NouveauLog('migration')
    })

    if ($ok -and (Test-Path -LiteralPath $sortie)) {
        [Affichage]::Ok(("Resultat : {0}" -f $sortie))
        [Affichage]::Aide('Filtrez la colonne STATUT : AJOUTEE, SUPPRIMEE, MODIFIEE.')
        if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
            Invoke-Item -LiteralPath $sortie
        }
    }
    [Affichage]::Pause()
}


function Invoke-RechercherDansFichiers {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('RECHERCHER UN TEXTE DANS PLUSIEURS FICHIERS')
    [Affichage]::Aide('Exemple : ou est utilisee la table KPA_PARTIES dans mes scripts ?')

    $dossier = [Saisie]::Texte('Dossier a explorer :', $Ctx.DossierDonnees)
    if (-not $dossier) { return }
    if (-not (Test-Path -LiteralPath $dossier)) {
        [Affichage]::Erreur('Dossier introuvable.')
        [Affichage]::Pause()
        return
    }

    $motif = [Saisie]::Texte('Texte a rechercher :', '')
    if (-not $motif) { return }

    $filtre = [Saisie]::Texte('Types de fichiers (ex : *.sql, *.txt, * pour tous) :', '*')
    if (-not $filtre) { return }

    $recursif = [Saisie]::Confirmer('Inclure les sous-dossiers ?')

    [Affichage]::Commande(("Get-ChildItem -Path `"{0}`" -Filter {1}{2} | Select-String -Pattern '{3}' -SimpleMatch" -f
        $dossier, $filtre, $(if ($recursif) { ' -Recurse' } else { '' }), $motif))

    [Affichage]::Separateur()

    # Recherche en flux : la memoire reste constante meme sur de gros fichiers,
    # et la regex n'est compilee qu'une seule fois.
    $rx = New-Object System.Text.RegularExpressions.Regex(
        ([regex]::Escape($motif)),
        [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')

    $params = @{ Path = $dossier; Filter = $filtre; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($recursif) { $params['Recurse'] = $true }

    $resultats = New-Object 'System.Collections.Generic.List[object]'
    $chrono = [System.Diagnostics.Stopwatch]::StartNew()
    $nbFichiers = 0

    foreach ($f in (Get-ChildItem @params)) {
        $nbFichiers = $nbFichiers + 1
        $num = 0
        $lecteur = $null
        try {
            $lecteur = New-Object System.IO.StreamReader($f.FullName)
            while ($null -ne ($ligne = $lecteur.ReadLine())) {
                $num = $num + 1
                if ($rx.IsMatch($ligne)) {
                    $resultats.Add([PSCustomObject]@{
                        Fichier = $f.Name
                        Ligne   = $num
                        Texte   = $ligne.Trim()
                        Chemin  = $f.FullName
                    })
                }
            }
        }
        catch { }
        finally { if ($lecteur) { $lecteur.Dispose() } }
    }
    $chrono.Stop()

    [Affichage]::Info(("{0} fichier(s) explore(s) en {1:N1}s" -f $nbFichiers, $chrono.Elapsed.TotalSeconds))

    if ($resultats.Count -eq 0) {
        [Affichage]::Attention('Aucune occurrence trouvee.')
    }
    else {
        [Affichage]::Ok(("{0} occurrence(s) trouvee(s)" -f $resultats.Count))
        $resultats | Select-Object -First 25 |
            Format-Table Fichier, Ligne, Texte -AutoSize |
            Out-String -Width 200 | Write-Host

        if ($resultats.Count -gt 25) {
            [Affichage]::Info(("... et {0} autre(s)" -f ($resultats.Count - 25)))
        }

        if ([Saisie]::Confirmer('Enregistrer la liste complete dans un fichier ?')) {
            $sortie = $Ctx.NouvelleSortie('recherche', '.csv')
            $texte = ($resultats | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
            [System.IO.File]::WriteAllText($sortie, $texte, (New-Object System.Text.UTF8Encoding($true)))
            [Affichage]::Ok(("Enregistre : {0}" -f $sortie))
        }
    }
    [Affichage]::Pause()
}


function Invoke-ExtraireDistincts {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('EXTRAIRE LES VALEURS UNIQUES D''UNE LISTE')
    [Affichage]::Aide('Supprime les doublons d''une colonne ou d''un fichier texte,')
    [Affichage]::Aide('et compte le nombre d''occurrences de chaque valeur.')

    $f = [Saisie]::Fichier('Fichier source :', $Ctx.DossierDonnees)
    if (-not $f) { return }

    $valeurs = New-Object 'System.Collections.Generic.List[string]'
    $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()

    if ($ext -match 'xls') {
        $s = [Saisie]::FeuilleExcel($f, 'Quelle feuille ?')
        if (-not $s) { return }
        $c = [Saisie]::ColonneExcel($f, $s, 'Quelle colonne ?')
        if (-not $c) { return }

        $excel = $null; $wb = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false; $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($f, 0, $true)
            $ws = $null
            foreach ($x in $wb.Worksheets) { if ($x.Name -eq $s) { $ws = $x; break } }

            $data = $ws.UsedRange.Value2
            $rMin = [int]$data.GetLowerBound(0); $rMax = [int]$data.GetUpperBound(0)
            $cMin = [int]$data.GetLowerBound(1); $cMax = [int]$data.GetUpperBound(1)

            $idx = 0
            for ($k = $cMin; $k -le $cMax; $k++) {
                $v = $data.GetValue($rMin, $k)
                if ($null -ne $v -and ([string]$v).Trim() -eq $c) { $idx = $k; break }
            }
            for ($r = $rMin + 1; $r -le $rMax; $r++) {
                $v = $data.GetValue($r, $idx)
                if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                    $valeurs.Add(([string]$v).Trim())
                }
            }
        }
        finally {
            if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
            if ($excel) { try { $excel.Quit() } catch { } }
            foreach ($o in @($wb, $excel)) {
                if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
            }
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }
    }
    else {
        $lecteur = New-Object System.IO.StreamReader($f)
        try {
            while ($null -ne ($l = $lecteur.ReadLine())) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { $valeurs.Add($l.Trim()) }
            }
        }
        finally { $lecteur.Dispose() }
    }

    if ($valeurs.Count -eq 0) {
        [Affichage]::Attention('Aucune valeur trouvee.')
        [Affichage]::Pause()
        return
    }

    # Comptage par dictionnaire : acces O(1), performant meme sur 1 million de valeurs
    $compteur = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($v in $valeurs) {
        if ($compteur.ContainsKey($v)) { $compteur[$v] = $compteur[$v] + 1 }
        else { $compteur[$v] = 1 }
    }

    $distincts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($cle in $compteur.Keys) {
        $distincts.Add([PSCustomObject]@{ VALEUR = $cle; OCCURRENCES = $compteur[$cle] })
    }
    $tries = $distincts | Sort-Object -Property @{ Expression = 'OCCURRENCES'; Descending = $true }, 'VALEUR'

    [Affichage]::Ok(("{0} valeurs lues, {1} valeurs distinctes" -f $valeurs.Count, $compteur.Count))
    $enDouble = @($tries | Where-Object { $_.OCCURRENCES -gt 1 })
    if ($enDouble.Count -gt 0) {
        [Affichage]::Attention(("{0} valeur(s) en doublon :" -f $enDouble.Count))
        $enDouble | Select-Object -First 15 | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
    }

    $sortie = $Ctx.NouvelleSortie('valeurs_distinctes', '.csv')
    $texte = ($tries | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
    [System.IO.File]::WriteAllText($sortie, $texte, (New-Object System.Text.UTF8Encoding($true)))
    [Affichage]::Ok(("Enregistre : {0}" -f $sortie))

    if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
        Invoke-Item -LiteralPath $sortie
    }
    [Affichage]::Pause()
}


function Invoke-FiltrerParListe {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('FILTRER UN TABLEAU A PARTIR D''UNE LISTE')
    [Affichage]::Aide('Exemple : extraire d''un fichier de 100 000 clients les 50 codes')
    [Affichage]::Aide('figurant dans une liste fournie a part.')

    $fData = [Saisie]::Fichier('Fichier a FILTRER (le grand tableau) :', $Ctx.DossierDonnees)
    if (-not $fData) { return }

    $sData = ''
    $extD = [System.IO.Path]::GetExtension($fData).ToLowerInvariant()
    if ($extD -match 'xls') {
        $sData = [Saisie]::FeuilleExcel($fData, 'Quelle feuille contient le tableau ?')
        if (-not $sData) { return }
        $cData = [Saisie]::ColonneExcel($fData, $sData, 'Quelle colonne sert de cle ?')
    }
    else {
        $cData = [Saisie]::Texte('Nom de la colonne servant de cle :', '')
    }
    if (-not $cData) { return }

    $fListe = [Saisie]::Fichier('Fichier contenant la LISTE des valeurs a garder :', $Ctx.DossierDonnees)
    if (-not $fListe) { return }

    # --- Chargement de la liste dans un HashSet : test d'appartenance en O(1) ---
    $aGarder = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $extL = [System.IO.Path]::GetExtension($fListe).ToLowerInvariant()

    if ($extL -match 'xls') {
        $sListe = [Saisie]::FeuilleExcel($fListe, 'Quelle feuille contient la liste ?')
        if (-not $sListe) { return }
        $cListe = [Saisie]::ColonneExcel($fListe, $sListe, 'Quelle colonne contient les valeurs ?')
        if (-not $cListe) { return }

        $excel = $null; $wb = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false; $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($fListe, 0, $true)
            $ws = $null
            foreach ($x in $wb.Worksheets) { if ($x.Name -eq $sListe) { $ws = $x; break } }
            $data = $ws.UsedRange.Value2
            $rMin = [int]$data.GetLowerBound(0); $rMax = [int]$data.GetUpperBound(0)
            $cMin = [int]$data.GetLowerBound(1); $cMax = [int]$data.GetUpperBound(1)
            $idx = 0
            for ($k = $cMin; $k -le $cMax; $k++) {
                $v = $data.GetValue($rMin, $k)
                if ($null -ne $v -and ([string]$v).Trim() -eq $cListe) { $idx = $k; break }
            }
            for ($r = $rMin + 1; $r -le $rMax; $r++) {
                $v = $data.GetValue($r, $idx)
                if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                    [void]$aGarder.Add(([string]$v).Trim())
                }
            }
        }
        finally {
            if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
            if ($excel) { try { $excel.Quit() } catch { } }
            foreach ($o in @($wb, $excel)) {
                if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
            }
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }
    }
    else {
        $lecteur = New-Object System.IO.StreamReader($fListe)
        try {
            while ($null -ne ($l = $lecteur.ReadLine())) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { [void]$aGarder.Add($l.Trim()) }
            }
        }
        finally { $lecteur.Dispose() }
    }

    [Affichage]::Info(("{0} valeur(s) dans la liste de filtrage" -f $aGarder.Count))

    # --- Filtrage du tableau ---
    $lignes = New-Object 'System.Collections.Generic.List[object]'

    if ($extD -match 'xls') {
        $excel = $null; $wb = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false; $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($fData, 0, $true)
            $ws = $null
            foreach ($x in $wb.Worksheets) { if ($x.Name -eq $sData) { $ws = $x; break } }
            $data = $ws.UsedRange.Value2
            $rMin = [int]$data.GetLowerBound(0); $rMax = [int]$data.GetUpperBound(0)
            $cMin = [int]$data.GetLowerBound(1); $cMax = [int]$data.GetUpperBound(1)

            $entetes = New-Object 'System.Collections.Generic.List[string]'
            $idx = 0
            for ($k = $cMin; $k -le $cMax; $k++) {
                $v = $data.GetValue($rMin, $k)
                $nom = if ($null -eq $v) { ("Col{0}" -f $k) } else { ([string]$v).Trim() }
                $entetes.Add($nom)
                if ($nom -eq $cData) { $idx = $k }
            }
            for ($r = $rMin + 1; $r -le $rMax; $r++) {
                $v = $data.GetValue($r, $idx)
                $cle = if ($null -eq $v) { '' } else { ([string]$v).Trim() }
                if (-not $aGarder.Contains($cle)) { continue }
                $obj = [ordered]@{}
                for ($k = $cMin; $k -le $cMax; $k++) {
                    $val = $data.GetValue($r, $k)
                    $obj[$entetes[$k - $cMin]] = if ($null -eq $val) { '' } else { [string]$val }
                }
                $lignes.Add([PSCustomObject]$obj)
            }
        }
        finally {
            if ($wb)    { try { $wb.Close($false) | Out-Null } catch { } }
            if ($excel) { try { $excel.Quit() } catch { } }
            foreach ($o in @($wb, $excel)) {
                if ($o) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
            }
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }
    }
    else {
        $importees = Import-Csv -LiteralPath $fData -Delimiter (Get-Separateur -Path $fData)
        foreach ($o in $importees) {
            $cle = [string]$o.$cData
            if ($aGarder.Contains($cle.Trim())) { $lignes.Add($o) }
        }
    }

    if ($lignes.Count -eq 0) {
        [Affichage]::Attention('Aucune ligne ne correspond a la liste.')
        [Affichage]::Aide('Verifiez que la colonne cle et les valeurs correspondent bien.')
        [Affichage]::Pause()
        return
    }

    [Affichage]::Ok(("{0} ligne(s) extraite(s)" -f $lignes.Count))
    $lignes | Select-Object -First 10 | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    $sortie = $Ctx.NouvelleSortie('extraction_filtree', '.csv')
    $texte = ($lignes | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
    [System.IO.File]::WriteAllText($sortie, $texte, (New-Object System.Text.UTF8Encoding($true)))
    [Affichage]::Ok(("Enregistre : {0}" -f $sortie))

    if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
        Invoke-Item -LiteralPath $sortie
    }
    [Affichage]::Pause()
}


function Get-Separateur {
    # Detecte le separateur d'un CSV en analysant les 5 premieres lignes.
    param([string]$Path)

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

    $meilleur = ';'; $meilleurScore = -1
    foreach ($sep in $candidats) {
        $comptes = New-Object 'System.Collections.Generic.List[int]'
        foreach ($l in $lignes) {
            $n = 0
            foreach ($ch in $l.ToCharArray()) { if ($ch -eq $sep) { $n = $n + 1 } }
            $comptes.Add($n)
        }
        $moy = ($comptes | Measure-Object -Average).Average
        if ($moy -lt 1) { continue }
        $regulier = (($comptes | Select-Object -Unique).Count -eq 1)
        $score = if ($regulier) { $moy * 10 } else { $moy }
        if ($score -gt $meilleurScore) { $meilleurScore = $score; $meilleur = $sep }
    }
    return $meilleur
}


function Invoke-AnalyserFichier {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('ANALYSER UN FICHIER INCONNU')
    [Affichage]::Aide('Repond a : combien de lignes ? quel separateur ? quel encodage ?')
    [Affichage]::Aide('quelles colonnes ? quel taux de remplissage ?')

    $f = [Saisie]::Fichier('Fichier a analyser :', $Ctx.DossierDonnees)
    if (-not $f) { return }

    $info = Get-Item -LiteralPath $f
    [Affichage]::Titre('IDENTITE DU FICHIER')
    [Affichage]::Info(("Nom          : {0}" -f $info.Name))
    [Affichage]::Info(("Taille       : {0:N2} Mo" -f ($info.Length / 1MB)))
    [Affichage]::Info(("Modifie le   : {0}" -f $info.LastWriteTime))

    # --- Encodage, d'apres la signature (BOM) ---
    $flux = [System.IO.File]::OpenRead($f)
    $tete = New-Object byte[] 4
    $lus = 0
    try { $lus = $flux.Read($tete, 0, 4) } finally { $flux.Dispose() }

    $encodage = 'ANSI ou UTF-8 sans BOM'
    if ($lus -ge 3 -and $tete[0] -eq 0xEF -and $tete[1] -eq 0xBB -and $tete[2] -eq 0xBF) {
        $encodage = 'UTF-8 avec BOM'
    }
    elseif ($lus -ge 2 -and $tete[0] -eq 0xFF -and $tete[1] -eq 0xFE) { $encodage = 'UTF-16 LE' }
    elseif ($lus -ge 2 -and $tete[0] -eq 0xFE -and $tete[1] -eq 0xFF) { $encodage = 'UTF-16 BE' }
    [Affichage]::Info(("Encodage     : {0}" -f $encodage))

    $ext = $info.Extension.ToLowerInvariant()
    if ($ext -match 'xls') {
        [Affichage]::Attention('Fichier Excel : utilisez plutot le menu de comparaison de colonnes.')
        [Affichage]::Pause()
        return
    }

    # --- Comptage des lignes en flux : memoire constante ---
    $nbLignes = 0
    $lecteur = New-Object System.IO.StreamReader($f)
    $premieres = New-Object 'System.Collections.Generic.List[string]'
    try {
        while ($null -ne ($l = $lecteur.ReadLine())) {
            $nbLignes = $nbLignes + 1
            if ($premieres.Count -lt 5) { $premieres.Add($l) }
        }
    }
    finally { $lecteur.Dispose() }
    [Affichage]::Info(("Lignes       : {0:N0}" -f $nbLignes))

    $sep = Get-Separateur -Path $f
    $sepAffiche = if ($sep -eq "`t") { 'TABULATION' } else { $sep }
    [Affichage]::Info(("Separateur   : {0}" -f $sepAffiche))

    [Affichage]::Titre('5 PREMIERES LIGNES')
    foreach ($l in $premieres) {
        $t = if ($l.Length -gt 150) { $l.Substring(0, 150) + '...' } else { $l }
        Write-Host ("   " + $t) -ForegroundColor Gray
    }

    # --- Profilage des colonnes ---
    if ([Saisie]::Confirmer('Analyser le contenu colonne par colonne ?')) {

        [Affichage]::Info('Analyse en cours...')
        $donnees = @(Import-Csv -LiteralPath $f -Delimiter $sep)

        if ($donnees.Count -eq 0) {
            [Affichage]::Attention('Aucune donnee exploitable.')
        }
        else {
            $total = $donnees.Count
            $profil = New-Object 'System.Collections.Generic.List[object]'

            foreach ($col in $donnees[0].PSObject.Properties.Name) {
                $distinctes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                $vides = 0
                $numeriques = 0
                $exemple = ''

                foreach ($d in $donnees) {
                    $v = $d.$col
                    if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { $vides = $vides + 1; continue }
                    $t = ([string]$v).Trim()
                    [void]$distinctes.Add($t)
                    if (-not $exemple) { $exemple = $t }
                    $tmp = [decimal]0
                    if ([decimal]::TryParse(($t -replace ',', '.'),
                            [System.Globalization.NumberStyles]::Any,
                            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$tmp)) {
                        $numeriques = $numeriques + 1
                    }
                }

                $remplies = $total - $vides
                $type = if ($remplies -eq 0) { 'VIDE' }
                        elseif ($numeriques -eq $remplies) { 'NUMERIQUE' }
                        elseif ($distinctes.Count -le 10) { 'CATEGORIE' }
                        else { 'TEXTE' }

                $profil.Add([PSCustomObject]@{
                    COLONNE     = $col
                    REMPLISSAGE = '{0:N0}%' -f (100 * $remplies / $total)
                    VIDES       = $vides
                    DISTINCTES  = $distinctes.Count
                    TYPE        = $type
                    EXEMPLE     = if ($exemple.Length -gt 25) { $exemple.Substring(0, 25) } else { $exemple }
                })
            }

            [Affichage]::Titre(("PROFIL DES COLONNES ({0} lignes analysees)" -f $total))
            $profil | Format-Table -AutoSize | Out-String -Width 160 | Write-Host

            $sortie = $Ctx.NouvelleSortie('profil_donnees', '.csv')
            $texte = ($profil | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
            [System.IO.File]::WriteAllText($sortie, $texte, (New-Object System.Text.UTF8Encoding($true)))
            [Affichage]::Ok(("Profil enregistre : {0}" -f $sortie))
        }
    }
    [Affichage]::Pause()
}


function Invoke-FusionnerFichiers {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('FUSIONNER PLUSIEURS FICHIERS CSV')
    [Affichage]::Aide('Exemple : consolider 30 exports quotidiens en un fichier mensuel.')
    [Affichage]::Aide('Les fichiers doivent avoir la meme structure de colonnes.')

    $dossier = [Saisie]::Texte('Dossier contenant les fichiers :', $Ctx.DossierDonnees)
    if (-not $dossier) { return }
    if (-not (Test-Path -LiteralPath $dossier)) {
        [Affichage]::Erreur('Dossier introuvable.')
        [Affichage]::Pause()
        return
    }

    $filtre = [Saisie]::Texte('Filtre de nom :', '*.csv')
    if (-not $filtre) { return }

    $fichiers = @(Get-ChildItem -LiteralPath $dossier -Filter $filtre -File)
    if ($fichiers.Count -eq 0) {
        [Affichage]::Attention('Aucun fichier correspondant.')
        [Affichage]::Pause()
        return
    }

    [Affichage]::Info(("{0} fichier(s) trouve(s) :" -f $fichiers.Count))
    foreach ($f in ($fichiers | Select-Object -First 10)) {
        [Affichage]::Aide(("  - {0} ({1:N0} octets)" -f $f.Name, $f.Length))
    }

    $ajouterSource = [Saisie]::Confirmer('Ajouter une colonne indiquant le fichier d''origine ?')
    if (-not [Saisie]::Confirmer('Lancer la fusion ?')) { return }

    $sortie = $Ctx.NouvelleSortie('fusion', '.csv')

    # Fusion EN FLUX : fonctionne meme avec des centaines de gros fichiers,
    # sans jamais charger l'ensemble en memoire.
    $encodage = New-Object System.Text.UTF8Encoding($true)
    $ecrivain = New-Object System.IO.StreamWriter($sortie, $false, $encodage)
    $enteteEcrit = $false
    $totalLignes = 0
    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        foreach ($f in $fichiers) {
            $lecteur = New-Object System.IO.StreamReader($f.FullName)
            try {
                $entete = $lecteur.ReadLine()
                if ($null -eq $entete) { continue }

                if (-not $enteteEcrit) {
                    if ($ajouterSource) { $ecrivain.WriteLine(("{0};FICHIER_SOURCE" -f $entete)) }
                    else { $ecrivain.WriteLine($entete) }
                    $enteteEcrit = $true
                }

                while ($null -ne ($ligne = $lecteur.ReadLine())) {
                    if ([string]::IsNullOrWhiteSpace($ligne)) { continue }
                    if ($ajouterSource) { $ecrivain.WriteLine(("{0};{1}" -f $ligne, $f.Name)) }
                    else { $ecrivain.WriteLine($ligne) }
                    $totalLignes = $totalLignes + 1
                }
            }
            finally { $lecteur.Dispose() }
            [Affichage]::Aide(("  fusionne : {0}" -f $f.Name))
        }
    }
    finally { $ecrivain.Dispose() }
    $chrono.Stop()

    [Affichage]::Ok(("{0} fichiers, {1:N0} lignes en {2:N1}s" -f $fichiers.Count, $totalLignes, $chrono.Elapsed.TotalSeconds))
    [Affichage]::Ok(("Enregistre : {0}" -f $sortie))

    if ([Saisie]::Confirmer('Ouvrir le resultat maintenant ?')) {
        Invoke-Item -LiteralPath $sortie
    }
    [Affichage]::Pause()
}


function Invoke-TraitementCre {
    param([ContexteToolkit]$Ctx, [Executeur]$Exec)

    [Affichage]::Cadre('TRAITEMENTS CRE (metier)')

    $choix = [Saisie]::Choix('Quel traitement ?', @(
        'Extraire les tables/colonnes des requetes CRE  (Extract-CreTableColumns)',
        'Resoudre les alias de vues                     (Resolve-CreViewAliases)'
    ))
    if ($choix -eq 0) { return }

    if ($choix -eq 1) {
        $x = [Saisie]::Fichier('Classeur CRE.xlsx :', $Ctx.DossierDonnees)
        if (-not $x) { return }
        $j = [Saisie]::Fichier('Fichier tables.json :', $Ctx.DossierDonnees)
        if (-not $j) { return }

        $sansEcriture = [Saisie]::Confirmer('Premier passage sans modifier le classeur (recommande) ?')
        $csv = $Ctx.NouvelleSortie('mapping_cre', '.csv')

        $Exec.Lancer('Extract-CreTableColumns.ps1', @{
            ExcelPath     = $x
            ConfigPath    = $j
            CsvPath       = $csv
            NoExcelOutput = $sansEcriture
        }) | Out-Null
    }
    else {
        $x = [Saisie]::Fichier('Classeur CRE.xlsx (contenant MAPPING_CRE) :', $Ctx.DossierDonnees)
        if (-not $x) { return }
        $b = [Saisie]::Fichier('Classeur base.xlsx :', $Ctx.DossierDonnees)
        if (-not $b) { return }
        $v = [Saisie]::Fichier('Fichier .txt des definitions de vues :', $Ctx.DossierDonnees)
        if (-not $v) { return }

        $sansEcriture = [Saisie]::Confirmer('Premier passage sans modifier le classeur (recommande) ?')
        $csv = $Ctx.NouvelleSortie('alias_vues', '.csv')

        $Exec.Lancer('Resolve-CreViewAliases.ps1', @{
            ExcelPath     = $x
            BasePath      = $b
            ViewsPath     = $v
            CsvPath       = $csv
            LogPath       = $Ctx.NouveauLog('alias')
            NoExcelOutput = $sansEcriture
        }) | Out-Null
    }
    [Affichage]::Pause()
}


function Invoke-CreerLaboTest {
    param([ContexteToolkit]$Ctx, [Executeur]$Exec)

    [Affichage]::Cadre('CREER UN JEU DE DONNEES DE TEST')
    [Affichage]::Aide('Genere des fichiers de test (CSV, Excel, TXT, XML, JSON, SQL)')
    [Affichage]::Aide('contenant volontairement des anomalies, pour essayer les outils')
    [Affichage]::Aide('sans risque sur vos vraies donnees.')

    $dest = [Saisie]::Texte('Dossier de destination :', (Join-Path $Ctx.DossierScripts 'LAB'))
    if (-not $dest) { return }

    $existe = Test-Path -LiteralPath $dest
    if ($existe) {
        [Affichage]::Attention('Ce dossier existe deja et sera ENTIEREMENT remplace.')
        if (-not [Saisie]::Confirmer('Continuer ?')) { return }
    }

    $ok = $Exec.Lancer('New-TestLab.ps1', @{ Path = $dest; Force = $existe })

    if ($ok) {
        [Affichage]::Ok('Laboratoire cree.')
        if ([Saisie]::Confirmer('Utiliser ce dossier comme dossier de donnees courant ?')) {
            $Ctx.DossierDonnees = (Resolve-Path -LiteralPath $dest).Path
            [Affichage]::Ok(("Dossier de donnees : {0}" -f $Ctx.DossierDonnees))
        }
    }
    [Affichage]::Pause()
}


function Invoke-Configurer {
    param([ContexteToolkit]$Ctx)

    [Affichage]::Cadre('CONFIGURATION')
    [Affichage]::Info(("Dossier des scripts : {0}" -f $Ctx.DossierScripts))
    [Affichage]::Info(("Dossier de donnees  : {0}" -f $Ctx.DossierDonnees))
    [Affichage]::Info(("Dossier des sorties : {0}" -f $Ctx.DossierSorties))
    [Affichage]::Info(("Dossier des logs    : {0}" -f $Ctx.DossierLogs))

    $choix = [Saisie]::Choix('Que modifier ?', @(
        'Le dossier de donnees',
        'Le dossier des sorties',
        'Afficher les informations systeme',
        'Afficher l''historique des commandes de cette session'
    ))

    switch ($choix) {
        1 {
            $d = [Saisie]::Texte('Nouveau dossier de donnees :', $Ctx.DossierDonnees)
            if ($d -and (Test-Path -LiteralPath $d)) {
                $Ctx.DossierDonnees = (Resolve-Path -LiteralPath $d).Path
                [Affichage]::Ok('Modifie.')
            }
            elseif ($d) { [Affichage]::Erreur('Dossier introuvable.') }
        }
        2 {
            $d = [Saisie]::Texte('Nouveau dossier de sorties :', $Ctx.DossierSorties)
            if ($d) {
                if (-not (Test-Path -LiteralPath $d)) {
                    New-Item -Path $d -ItemType Directory -Force | Out-Null
                }
                $Ctx.DossierSorties = (Resolve-Path -LiteralPath $d).Path
                $Ctx.DossierLogs = Join-Path $Ctx.DossierSorties '_logs'
                if (-not (Test-Path -LiteralPath $Ctx.DossierLogs)) {
                    New-Item -Path $Ctx.DossierLogs -ItemType Directory -Force | Out-Null
                }
                [Affichage]::Ok('Modifie.')
            }
        }
        3 {
            [Affichage]::Titre('INFORMATIONS SYSTEME')
            $estAdmin = $false
            try {
                $id = [Security.Principal.WindowsIdentity]::GetCurrent()
                $pr = New-Object Security.Principal.WindowsPrincipal($id)
                $estAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            }
            catch { }

            [Affichage]::Info(("PowerShell         : {0}" -f $PSVersionTable.PSVersion.ToString()))
            [Affichage]::Info(("Edition            : {0}" -f $PSVersionTable.PSEdition))
            [Affichage]::Info(("Machine            : {0}" -f $env:COMPUTERNAME))
            [Affichage]::Info(("Utilisateur        : {0}" -f $env:USERNAME))
            [Affichage]::Info(("Administrateur     : {0}" -f $(if ($estAdmin) { 'oui' } else { 'non (normal)' })))
            [Affichage]::Info(("Politique execution: {0}" -f (Get-ExecutionPolicy).ToString()))
            [Affichage]::Info(("Culture            : {0}" -f (Get-Culture).Name))

            $excelOk = $false
            try {
                $t = New-Object -ComObject Excel.Application
                $excelOk = $true
                $t.Quit()
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($t)
            }
            catch { }
            [Affichage]::Info(("Excel disponible   : {0}" -f $(if ($excelOk) { 'oui' } else { 'NON' })))

            [Affichage]::Titre('SCRIPTS DU PACKAGE')
            foreach ($s in @('Compare-DataFiles.ps1', 'Resolve-CreViewAliases.ps1',
                             'Extract-CreTableColumns.ps1', 'New-TestLab.ps1')) {
                if ($Ctx.ScriptExiste($s)) { [Affichage]::Ok($s) }
                else { [Affichage]::Attention(("{0} (absent)" -f $s)) }
            }
        }
        4 {
            [Affichage]::Titre('HISTORIQUE DES COMMANDES')
            if ($Ctx.Historique.Count -eq 0) {
                [Affichage]::Info('Aucune commande lancee pour le moment.')
            }
            else {
                foreach ($c in $Ctx.Historique) {
                    Write-Host ("   " + $c) -ForegroundColor Yellow
                }
                [Affichage]::Aide('Vous pouvez copier ces commandes pour les rejouer directement.')
            }
        }
    }
    [Affichage]::Pause()
}


# ##############################################################################
# PROGRAMME PRINCIPAL
# ##############################################################################

try {
    $dossierScripts = $PSScriptRoot
    if (-not $dossierScripts) { $dossierScripts = (Get-Location).Path }

    if (-not $DataFolder)   { $DataFolder   = $dossierScripts }
    if (-not $OutputFolder) { $OutputFolder = Join-Path $dossierScripts 'SORTIES' }

    if (-not (Test-Path -LiteralPath $DataFolder)) {
        Write-Host ("Dossier de donnees introuvable : {0}" -f $DataFolder) -ForegroundColor Yellow
        $DataFolder = $dossierScripts
    }

    $contexte = [ContexteToolkit]::new(
        $dossierScripts,
        (Resolve-Path -LiteralPath $DataFolder).Path,
        $OutputFolder)

    $executeur = [Executeur]::new($contexte)

    $continuer = $true
    while ($continuer) {

        [Affichage]::Effacer()
        [Affichage]::Cadre('BOITE A OUTILS ETL - MENU PRINCIPAL')

        Write-Host ''
        Write-Host '   COMPARER' -ForegroundColor Cyan
        Write-Host '     1. Comparer deux fichiers texte ou CSV'
        Write-Host '     2. Comparer deux colonnes Excel'
        Write-Host '     3. Controler une migration (avant / apres, champ par champ)'
        Write-Host ''
        Write-Host '   EXPLORER' -ForegroundColor Cyan
        Write-Host '     4. Analyser un fichier inconnu (structure, qualite)'
        Write-Host '     5. Rechercher un texte dans plusieurs fichiers'
        Write-Host ''
        Write-Host '   TRANSFORMER' -ForegroundColor Cyan
        Write-Host '     6. Extraire les valeurs uniques / detecter les doublons'
        Write-Host '     7. Filtrer un tableau a partir d''une liste'
        Write-Host '     8. Fusionner plusieurs fichiers CSV'
        Write-Host ''
        Write-Host '   METIER' -ForegroundColor Cyan
        Write-Host '     9. Traitements CRE (mapping, alias de vues)'
        Write-Host ''
        Write-Host '   OUTILS' -ForegroundColor Cyan
        Write-Host '    10. Creer un jeu de donnees de test'
        Write-Host '    11. Configuration et informations systeme'
        Write-Host ''
        Write-Host '     0. Quitter' -ForegroundColor DarkGray
        Write-Host ''
        [Affichage]::Separateur()
        Write-Host ("   Donnees : {0}" -f $contexte.DossierDonnees) -ForegroundColor DarkGray
        Write-Host ("   Sorties : {0}" -f $contexte.DossierSorties) -ForegroundColor DarkGray

        $reponse = Read-Host '   Votre choix'

        switch ($reponse.Trim()) {
            '1'  { Invoke-ComparerFichiers      -Ctx $contexte -Exec $executeur }
            '2'  { Invoke-ComparerColonnes      -Ctx $contexte -Exec $executeur }
            '3'  { Invoke-ControlerMigration    -Ctx $contexte -Exec $executeur }
            '4'  { Invoke-AnalyserFichier       -Ctx $contexte }
            '5'  { Invoke-RechercherDansFichiers -Ctx $contexte }
            '6'  { Invoke-ExtraireDistincts     -Ctx $contexte }
            '7'  { Invoke-FiltrerParListe       -Ctx $contexte }
            '8'  { Invoke-FusionnerFichiers     -Ctx $contexte }
            '9'  { Invoke-TraitementCre         -Ctx $contexte -Exec $executeur }
            '10' { Invoke-CreerLaboTest         -Ctx $contexte -Exec $executeur }
            '11' { Invoke-Configurer            -Ctx $contexte }
            '0'  { $continuer = $false }
            default {
                Write-Host '   Choix non reconnu.' -ForegroundColor Yellow
                Start-Sleep -Milliseconds 900
            }
        }
    }

    [Affichage]::Effacer()
    [Affichage]::Cadre('AU REVOIR')
    if ($contexte.Historique.Count -gt 0) {
        [Affichage]::Titre('Commandes lancees pendant cette session')
        foreach ($c in $contexte.Historique) {
            Write-Host ("   " + $c) -ForegroundColor Yellow
        }
        Write-Host ''
        [Affichage]::Aide('Copiez-les pour automatiser vos traitements recurrents.')
    }
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host ('#' * 78) -ForegroundColor Red
    Write-Host '#  ERREUR DE L''INTERFACE' -ForegroundColor Red
    Write-Host ('#' * 78) -ForegroundColor Red
    Write-Host ("#  MESSAGE   : {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host ("#  LIGNE     : {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
        if ($_.InvocationInfo.Line) {
            Write-Host ("#  CODE      : {0}" -f $_.InvocationInfo.Line.Trim()) -ForegroundColor Yellow
        }
    }
    Write-Host ("#  TYPE .NET : {0}" -f $_.Exception.GetType().FullName) -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        foreach ($l in ($_.ScriptStackTrace -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($l)) {
                Write-Host ("#    {0}" -f $l.Trim()) -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ('#' * 78) -ForegroundColor Red
    Write-Host ''
    Write-Host 'Appuyez sur Entree pour fermer...' -ForegroundColor DarkGray
    [void](Read-Host)
    exit 1
}
