<#
================================================================================
 New-TestLab.ps1  -  Generateur de laboratoire de test ETL
================================================================================

 A QUOI CA SERT
 --------------
 Genere un jeu de donnees COMPLET pour tester tous les utilitaires du package,
 dans un dossier de votre choix. Les fichiers produits contiennent
 volontairement des cas pieges : doublons, accents, encodages differents,
 separateurs varies, lignes vides, casse incoherente, valeurs manquantes.

 UTILISATION
 -----------
   .\New-TestLab.ps1                        # cree .\LAB a cote du script
   .\New-TestLab.ps1 -Path "D:\MonLab"      # cree ailleurs
   .\New-TestLab.ps1 -Path "D:\Lab" -Force  # ecrase un lab existant
   .\New-TestLab.ps1 -NoExcel               # sans Excel (CSV/TXT/XML/JSON seuls)

 CE QUI EST GENERE
 -----------------
   01_TEXTE/    vues SQL (2 versions), logs, listes, fichier a largeur fixe
   02_CSV/      exports avec separateurs et encodages varies, doublons
   03_XML_JSON/ configuration et referentiels
   04_EXCEL/    CRE.xlsx (4 feuilles) et base.xlsx (2 feuilles)
   05_SQL/      script de creation + jeu de donnees SQL Server
   LISEZMOI.txt inventaire et scenarios de test

 PREREQUIS : Excel installe (sauf avec -NoExcel). AUCUN droit administrateur.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Path = '',
    [switch]$Force,
    [switch]$NoExcel,
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'


# ##############################################################################
# CLASSE : journal d'execution
# ##############################################################################
# PowerShell 5.0+ supporte les vraies classes. On les utilise ici pour
# regrouper l'etat (chemin du log, niveau d'indentation) et les comportements
# associes, plutot que de disperser des variables globales.

class Journal {

    [string] $FichierLog
    [int]    $Niveau
    [int]    $NumeroEtape
    [datetime] $Debut

    Journal([string]$fichierLog) {
        $this.FichierLog  = $fichierLog
        $this.Niveau      = 0
        $this.NumeroEtape = 0
        $this.Debut       = Get-Date

        if ($this.FichierLog) {
            $dossier = Split-Path -Path $this.FichierLog -Parent
            if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
                New-Item -Path $dossier -ItemType Directory -Force | Out-Null
            }
        }
    }

    # Ecriture bas niveau : console + fichier
    [void] Ecrire([string]$texte, [string]$couleur) {
        Write-Host $texte -ForegroundColor $couleur
        if ($this.FichierLog) {
            try {
                Add-Content -LiteralPath $this.FichierLog -Encoding UTF8 `
                    -Value ("{0} | {1}" -f (Get-Date -Format 'HH:mm:ss'), $texte)
            }
            catch { }
        }
    }

    [void] Titre([string]$texte) {
        $this.Ecrire(('=' * 78), 'DarkGray')
        $this.Ecrire($texte, 'Cyan')
        $this.Ecrire(('=' * 78), 'DarkGray')
    }

    [void] Etape([string]$nom) {
        $this.NumeroEtape = $this.NumeroEtape + 1
        $ind = '  ' * $this.Niveau
        $this.Ecrire(("{0}> ETAPE {1} : {2}" -f $ind, $this.NumeroEtape, $nom), 'Cyan')
        $this.Niveau = $this.Niveau + 1
    }

    [void] FinEtape() {
        if ($this.Niveau -gt 0) { $this.Niveau = $this.Niveau - 1 }
    }

    [void] Info([string]$texte)   { $this.Ecrire(('  ' * $this.Niveau + '[i] ' + $texte), 'White') }
    [void] Ok([string]$texte)     { $this.Ecrire(('  ' * $this.Niveau + '[+] ' + $texte), 'Green') }
    [void] Attention([string]$t)  { $this.Ecrire(('  ' * $this.Niveau + '[!] ' + $t), 'Yellow') }
    [void] Erreur([string]$texte) { $this.Ecrire(('  ' * $this.Niveau + '[X] ' + $texte), 'Red') }
    [void] Detail([string]$texte) { $this.Ecrire(('  ' * $this.Niveau + '    ' + $texte), 'Gray') }

    [string] Duree() {
        $d = (Get-Date) - $this.Debut
        if ($d.TotalSeconds -lt 60) { return ("{0:N1}s" -f $d.TotalSeconds) }
        return ("{0:N0} min {1:N0}s" -f $d.TotalMinutes, $d.Seconds)
    }
}


# ##############################################################################
# CLASSE : ecriture de fichiers texte avec controle de l'encodage
# ##############################################################################

class EcrivainTexte {

    # UTF-8 SANS BOM : attendu par SQL Server, les outils Unix, ConvertFrom-Json
    static [void] EcrireUtf8SansBom([string]$chemin, [string[]]$lignes) {
        [EcrivainTexte]::PreparerDossier($chemin)
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($chemin, ($lignes -join "`r`n"), $enc)
    }

    # UTF-8 AVEC BOM : necessaire pour qu'Excel affiche correctement les accents
    static [void] EcrireUtf8AvecBom([string]$chemin, [string[]]$lignes) {
        [EcrivainTexte]::PreparerDossier($chemin)
        $enc = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($chemin, ($lignes -join "`r`n"), $enc)
    }

    # ANSI / Windows-1252 : encodage des vieux exports metier.
    # Utilise EXPLICITEMENT le codepage 1252 plutot que [Encoding]::Default :
    # ce dernier depend de la configuration regionale de la machine et peut,
    # sur certains postes recents (option "UTF-8 beta" de Windows activee),
    # etre en realite de l'UTF-8 - ce qui rendrait ce fichier de test
    # indistinguable d'un fichier UTF-8 et fausserait sa detection.
    static [void] EcrireAnsi([string]$chemin, [string[]]$lignes) {
        [EcrivainTexte]::PreparerDossier($chemin)
        $enc = [System.Text.Encoding]::GetEncoding(1252)
        [System.IO.File]::WriteAllText($chemin, ($lignes -join "`r`n"), $enc)
    }

    static [void] PreparerDossier([string]$chemin) {
        $dossier = Split-Path -Path $chemin -Parent
        if ($dossier -and -not (Test-Path -LiteralPath $dossier)) {
            New-Item -Path $dossier -ItemType Directory -Force | Out-Null
        }
    }
}


# ##############################################################################
# CLASSE : construction de classeurs Excel multi-feuilles
# ##############################################################################

class ConstructeurExcel {

    [object] $Excel
    [object] $Classeur
    [Journal] $Log

    ConstructeurExcel([Journal]$log) {
        $this.Log = $log
        $this.Excel = New-Object -ComObject Excel.Application
        $this.Excel.Visible        = $false
        $this.Excel.DisplayAlerts  = $false
        $this.Excel.ScreenUpdating = $false
        $this.Excel.EnableEvents   = $false
        $this.Classeur = $this.Excel.Workbooks.Add()
    }

    # Ajoute une feuille remplie de donnees.
    # $donnees = tableau de tableaux : la premiere ligne est l'entete.
    # Ecriture CELLULE PAR CELLULE : volontaire. L'ecriture en bloc d'un
    # tableau 2D provoque des erreurs de marshaling COM (OutOfMemoryException
    # trompeuse) selon les versions d'Excel.
    [void] AjouterFeuille([string]$nom, [object[]]$donnees) {

        $feuille = $this.Classeur.Worksheets.Add(
            [Type]::Missing,
            $this.Classeur.Worksheets.Item($this.Classeur.Worksheets.Count))
        $feuille.Name = $nom

        $nbLignes = $donnees.Count
        for ($l = 0; $l -lt $nbLignes; $l++) {
            $ligne = $donnees[$l]
            for ($c = 0; $c -lt $ligne.Count; $c++) {
                $valeur = $ligne[$c]
                if ($null -eq $valeur) { continue }

                # TOUJOURS assigner une CHAINE, jamais un entier ou un decimal.
                # L'adaptateur COM de PowerShell met en cache la signature du
                # setter Value2 lors du PREMIER appel. Si la premiere valeur
                # ecrite est une chaine et qu'une valeur suivante est un entier,
                # l'appel echoue avec :
                #   "Impossible d'effectuer un cast d'un objet de type
                #    'System.Int32' en type 'System.String'."
                # Excel convertit de lui-meme les chaines numeriques en nombres.
                $texte = [string]$valeur
                if ($texte.Length -eq 0) { continue }

                $feuille.Cells.Item($l + 1, $c + 1).Value2 = $texte
            }
        }

        # Mise en forme de l'entete
        if ($nbLignes -gt 0) {
            $nbCols = $donnees[0].Count
            $entete = $feuille.Range($feuille.Cells.Item(1, 1), $feuille.Cells.Item(1, $nbCols))
            $entete.Font.Bold = $true
            $entete.Interior.Color = 65535          # jaune
            try { $entete.AutoFilter() | Out-Null } catch { }
            for ($c = 1; $c -le $nbCols; $c++) {
                $feuille.Columns.Item($c).ColumnWidth = 28
            }
        }

        $this.Log.Detail(("feuille '{0}' : {1} lignes" -f $nom, ($nbLignes - 1)))
    }

    [void] Enregistrer([string]$chemin) {
        # Suppression des feuilles vides creees par defaut par Excel
        $aSupprimer = New-Object 'System.Collections.Generic.List[object]'
        foreach ($f in $this.Classeur.Worksheets) {
            if ($f.Name -like 'Feuil*' -or $f.Name -like 'Sheet*') { $aSupprimer.Add($f) }
        }
        foreach ($f in $aSupprimer) {
            if ($this.Classeur.Worksheets.Count -gt 1) { $f.Delete() }
        }

        [EcrivainTexte]::PreparerDossier($chemin)
        if (Test-Path -LiteralPath $chemin) { Remove-Item -LiteralPath $chemin -Force }

        $this.Classeur.SaveAs($chemin, 51)      # 51 = format xlsx
        $this.Log.Ok(("classeur ecrit : {0}" -f (Split-Path -Path $chemin -Leaf)))
    }

    # Liberation COM : sans elle, EXCEL.EXE reste en memoire indefiniment
    [void] Fermer() {
        if ($this.Classeur) { try { $this.Classeur.Close($false) | Out-Null } catch { } }
        if ($this.Excel) {
            try { $this.Excel.ScreenUpdating = $true } catch { }
            try { $this.Excel.Quit() } catch { }
        }
        foreach ($o in @($this.Classeur, $this.Excel)) {
            if ($o) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { }
            }
        }
        $this.Classeur = $null
        $this.Excel = $null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}


# ##############################################################################
# PROGRAMME PRINCIPAL
# ##############################################################################

if (-not $Path) { $Path = Join-Path -Path $PSScriptRoot -ChildPath 'LAB' }
$journal = [Journal]::new($LogPath)

try {
    $journal.Titre('GENERATION DU LABORATOIRE DE TEST ETL')
    $journal.Info(("Destination : {0}" -f $Path))
    $journal.Info(("PowerShell  : {0}" -f $PSVersionTable.PSVersion.ToString()))

    # ----------------------------------------------------------------------
    $journal.Etape('Preparation du dossier')

    if (Test-Path -LiteralPath $Path) {
        if (-not $Force) {
            throw ("Le dossier existe deja : {0}. Utilisez -Force pour l'ecraser." -f $Path)
        }
        Remove-Item -LiteralPath $Path -Recurse -Force
        $journal.Attention('Dossier existant supprime (-Force)')
    }
    New-Item -Path $Path -ItemType Directory -Force | Out-Null

    $dTexte  = Join-Path $Path '01_TEXTE'
    $dCsv    = Join-Path $Path '02_CSV'
    $dXml    = Join-Path $Path '03_XML_JSON'
    $dExcel  = Join-Path $Path '04_EXCEL'
    $dSql    = Join-Path $Path '05_SQL'
    $dSortie = Join-Path $Path '99_SORTIES'

    foreach ($d in @($dTexte, $dCsv, $dXml, $dExcel, $dSql, $dSortie)) {
        New-Item -Path $d -ItemType Directory -Force | Out-Null
    }
    $journal.Ok('6 sous-dossiers crees')
    $journal.FinEtape()


    # ======================================================================
    $journal.Etape('01_TEXTE - definitions de vues SQL')

    # Ce fichier reproduit TOUS les cas pieges observes en production :
    #  - CREATE VIEW avec et sans schema [dbo].
    #  - corps entoure de parentheses
    #  - commentaires de fin de ligne
    #  - cast(... as TYPE) : le 'as' interne ne doit pas etre pris pour l'alias
    #  - alias implicite (colonne sans AS)
    #  - SELECT DISTINCT
    #  - absence de GO entre les vues
    $vues = @(
        'CREATE VIEW [dbo].[V_TFT_K_TIERS] AS',
        'SELECT  T.NAME                AS NOM_TIERS',
        '     ,  T.FIRST_NAME          AS PRENOM_TIERS',
        '     ,  T.PARTICULE           AS PARTICULE_NOM',
        '     ,  T.MAIDEN_NAME         AS NOM_JEUNE_FILLE',
        '     ,  T.MARITAL_STATUS      AS SITUATION_FAMILIALE',
        '     ,  T.PARTY_ID',
        '     ,  T.STATUS              AS STATUT',
        'FROM TFT.dbo.TFT_K_TIERS AS T',
        'INNER JOIN IC.dbo.ODS_C_USERS AS U ON U.ID_EXTERNE_KELIA = T.CREATED_BY_USER_ID',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_TIERS_1] AS',
        'SELECT  T.NAME                AS RAISON_SOCIALE',
        '     ,  T.FIRST_NAME          AS PRENOM',
        '     ,  T.PARTICULE           AS PARTICULE',
        '     ,  T.MAIDEN_NAME         AS NOM_NAISSANCE',
        'FROM TFT.dbo.TFT_K_TIERS AS T',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_TIERS_2] AS',
        'SELECT  T.NAME                AS DENOMINATION',
        '     ,  T.BANNER              AS ENSEIGNE',
        '     ,  T.SIRET_CODE          AS NUMERO_SIRET',
        '     ,  T.REMARKS             AS COMMENTAIRES',
        'FROM TFT.dbo.TFT_K_TIERS AS T',
        '',
        '-- Vue SANS schema, corps entre parentheses, SELECT DISTINCT',
        'CREATE VIEW V_TFT_K_PLACES_COTATION AS',
        '(',
        '    select distinct MARKET_PLACE_NAME   AS LIBELLE_PLACE_COTATION',
        '         , MARKET_PLACE_ID              AS CODE_KELIA',
        '    from TFT..TFT_K_SUPPORTS',
        '    where MARKET_PLACE_NAME IS NOT NULL AND MARKET_PLACE_NAME <> '' ''',
        ')',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_ADRESSES] AS',
        'SELECT  A.LINE0               AS ADRESSE_LIGNE_1',
        '     ,  A.LINE1               AS ADRESSE_LIGNE_2',
        '     ,  A.LINE2               AS ADRESSE_LIGNE_3',
        '     ,  A.LINE3               AS ADRESSE_LIGNE_4',
        '     ,  A.ZIP_CODE            AS CODE_POSTAL',
        '     ,  A.CITY                AS VILLE',
        'FROM TFT.dbo.TFT_K_ADRESSES AS A',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_ADRESSES_VALIDES] AS',
        'SELECT  A.LINE0               AS ADR_L1_VALIDE',
        '     ,  A.ZIP_CODE            AS CP_VALIDE',
        'FROM TFT.dbo.TFT_K_ADRESSES AS A',
        'WHERE A.STATUS = 1',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_RIB_KELIA] AS',
        'SELECT  B.ACCOUNT_NUMBER      AS NUMERO_COMPTE',
        '     ,  B.ACCOUNT_HOLDER      AS TITULAIRE_COMPTE',
        '     ,  B.IBAN_ACCOUNT        AS IBAN',
        '     ,  B.BIC_CODE            AS CODE_BIC',
        'FROM TFT.dbo.TFT_K_RIB_KELIA AS B',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_COORDONNEES_BANCAIRES] AS',
        'SELECT  B.ACCOUNT_NUMBER      AS NUM_COMPTE_BANCAIRE',
        '     ,  B.ACCOUNT_HOLDER      AS NOM_TITULAIRE',
        'FROM TFT.dbo.TFT_K_COORDONNEES_BANCAIRES AS B',
        '',
        '-- Cas piege : cast(... as TYPE) ET commentaires de fin de ligne',
        'CREATE VIEW V_TFT_K_TIERS_DONNEES_COMPLEMENTAIRES_DETAIL_PATRIMOINE AS',
        'SELECT',
        '    ID_TIERS_DONNEES_COMPLEMENTAIRES,',
        '    ROW_NUM,',
        '    cast(COL_NUM_0 as INT)          AS ID_SITUATION_PATRIMONIALE,   -- CODIF 813',
        '    cast(COL_NUM_1 as INT)          AS ID_REVENUS_FOYER_FISCAL,     -- CODIF 198',
        '    CAST(COL_NUM_3 AS NUMERIC(28,10)) AS MONTANT,',
        '    CAST(COL_NUM_6 AS VARCHAR(400)) AS AUTRE_REPARTITION_PATRIMOINE',
        'FROM V_TFT_K_TIERS_DONNEES_COMPLEMENTAIRES_ASSET_POSITION_VARCHAR',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_BENEFICIAIRES_CONTRAT] AS',
        'SELECT  BE.BENEF_NAME         AS NOM_BENEFICIAIRE',
        '     ,  BE.BENEF_FIRST_NAME   AS PRENOM_BENEFICIAIRE',
        '     ,  BE.RANK               AS RANG',
        'FROM TFT.dbo.TFT_K_BENEFICIAIRES AS BE',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_CLAUSES_BENEFICIAIRES] AS',
        'SELECT  C.DEATH_CLAUSE_TEXT   AS TEXTE_CLAUSE_DECES',
        'FROM TFT.dbo.TFT_K_CLAUSES_BENEFICIAIRES AS C',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_DECAISSEMENTS] AS',
        'SELECT  P.BANK_ACCOUNT        AS COMPTE_BANCAIRE',
        '     ,  P.AMOUNT              AS MONTANT_DECAISSE',
        'FROM TFT.dbo.TFT_K_DECAISSEMENTS AS P',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_CONTACTS] AS',
        'SELECT  CO.CONTACT_NAME       AS NOM_CONTACT',
        '     ,  CO.CONTACT_EMAIL      AS COURRIEL',
        'FROM TFT.dbo.TFT_K_CONTACTS AS CO',
        '',
        'CREATE VIEW [dbo].[V_TFT_K_REGROUPEMENTS_COMPTES_TRESORERIE] AS',
        'SELECT  G.COMMENT_TEXT        AS TEXTE_COMMENTAIRE',
        'FROM TFT.dbo.TFT_K_REGROUPEMENTS_COMPTES_TRESORERIE AS G'
    )
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'vues.txt'), $vues)
    $journal.Ok('vues.txt (14 vues, tous les cas pieges)')

    # Version 2 : sert a tester la comparaison de deux versions d'un fichier
    $vues2 = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $vues) { $vues2.Add($l) }
    $vues2[1] = 'SELECT  T.NAME                AS NOM_DU_TIERS'          # alias modifie
    $vues2.Add('')
    $vues2.Add('CREATE VIEW [dbo].[V_TFT_K_NOUVELLE_VUE] AS')            # vue ajoutee
    $vues2.Add('SELECT  N.LIBELLE             AS LIBELLE_NOUVEAU')
    $vues2.Add('FROM TFT.dbo.TFT_K_NOUVELLE AS N')
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'vues_v2.txt'), $vues2)
    $journal.Ok('vues_v2.txt (1 alias modifie + 1 vue ajoutee)')

    # Liste simple, avec doublons et casse incoherente
    $listeA = @(
        'CRE_ADDRESSES', 'CRE_BANK_ACCOUNTS', 'CRE_FUNDS', 'CRE_ORGANIZATIONS',
        'CRE_PARTIES', 'CRE_PARTIES_MEDIUM', 'CRE_PARTY_ADDRESSES',
        'CRE_PARTY_BANK_ACCOUNTS', 'CRE_PARTY_CONTACTS', 'CRE_PAYMENTS',
        'CRE_PERSONS', 'cre_parties', 'CRE_FUNDS', ''
    )
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'liste_A.txt'), $listeA)

    $listeB = @(
        'CRE_ADDRESSES', 'CRE_BANK_ACCOUNTS', 'CRE_FUNDS', 'CRE_ORGANIZATIONS',
        'CRE_PARTIES', 'CRE_POLICY_BENEFICIARIES', 'CRE_RECEIPTS',
        'CRE_RELATIONSHIP', 'CRE_TREASURY_ACCOUNT_GROUP'
    )
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'liste_B.txt'), $listeB)
    $journal.Ok('liste_A.txt / liste_B.txt (doublons, casse, ligne vide)')

    # Journal applicatif : test de recherche par motif
    $log = New-Object 'System.Collections.Generic.List[string]'
    $codesErreur = @('ORA-01555', 'ORA-00942', 'ORA-01017', 'ORA-12154')
    for ($j = 1; $j -le 300; $j++) {
        $h = '{0:D2}:{1:D2}:{2:D2}' -f (($j * 7) % 24), (($j * 13) % 60), (($j * 29) % 60)
        if ($j % 17 -eq 0) {
            $log.Add(("2026-08-1{0} {1} ERROR  Echec du chargement : {2} table KPA_PARTIES" -f ($j % 9), $h, $codesErreur[$j % 4]))
        }
        elseif ($j % 7 -eq 0) {
            $log.Add(("2026-08-1{0} {1} WARN   Ligne rejetee : cle absente du referentiel" -f ($j % 9), $h))
        }
        else {
            $log.Add(("2026-08-1{0} {1} INFO   Traitement du lot {2} : {3} lignes" -f ($j % 9), $h, $j, ($j * 137)))
        }
    }
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'traitement.log'), $log)
    $journal.Ok(("traitement.log ({0} lignes, erreurs ORA-*)" -f $log.Count))

    # Fichier a largeur fixe (export mainframe)
    $fixe = New-Object 'System.Collections.Generic.List[string]'
    $fixe.Add('CODE      LIBELLE                                 MONTANT     ')
    $noms = @('Alpha SARL', 'Beta SA', 'Gamma SAS', 'Delta EURL', 'Epsilon SCI')
    for ($j = 1; $j -le 40; $j++) {
        $code = 'CLI{0:D5}' -f $j
        $lib  = $noms[$j % 5]
        $mnt  = '{0:N2}' -f ($j * 1234.56)
        $fixe.Add(('{0,-10}{1,-40}{2,12}' -f $code, $lib, $mnt))
    }
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dTexte 'export_largeur_fixe.txt'), $fixe)
    $journal.Ok('export_largeur_fixe.txt (40 lignes)')

    $journal.FinEtape()


    # ======================================================================
    $journal.Etape('02_CSV - exports avec separateurs et encodages varies')

    # --- Referentiel clients : point-virgule, UTF-8 avec BOM, accents ---
    $clients = New-Object 'System.Collections.Generic.List[string]'
    $clients.Add('CODE_CLIENT;RAISON_SOCIALE;VILLE;REGION;MONTANT;DATE_CREATION;STATUT')
    $villes  = @('Paris', 'Lyon', 'Marseille', 'Bordeaux', 'Lille', 'Nantes')
    $regions = @('Ile-de-France', 'Auvergne-Rhone-Alpes', 'PACA', 'Nouvelle-Aquitaine', 'Hauts-de-France', 'Pays de la Loire')
    $societes = @('Etablissements Muller', 'Societe Generale du Batiment', 'Cabinet Andre & Fils',
                  'Enterprise Cotiere', 'Groupe Herisson', 'Maison Provencale')
    for ($j = 1; $j -le 200; $j++) {
        $statut = if ($j % 11 -eq 0) { 'Invalide' } else { 'Valide' }
        $mnt = '{0:N2}' -f ($j * 137.45)
        $clients.Add(('CLI{0:D4};{1} {2};{3};{4};{5};2026-0{6}-1{7};{8}' -f
            $j, $societes[$j % 6], $j, $villes[$j % 6], $regions[$j % 6], $mnt, (($j % 9) + 1), ($j % 9), $statut))
    }
    # Doublons volontaires (test de detection)
    $clients.Add('CLI0007;Etablissements Muller 7;Bordeaux;Nouvelle-Aquitaine;961,15;2026-08-17;Valide')
    $clients.Add('CLI0042;Enterprise Cotiere 42;Lyon;Auvergne-Rhone-Alpes;5772,90;2026-07-16;Valide')
    # Lignes de mauvaise qualite (test de controle qualite)
    $clients.Add('CLI9998;;Paris;Ile-de-France;-500,00;2026-08-01;Inconnu')
    $clients.Add('XXX123;Societe Sans Code Valide;Nice;PACA;abc;pas-une-date;Valide')
    [EcrivainTexte]::EcrireUtf8AvecBom((Join-Path $dCsv 'clients.csv'), $clients)
    $journal.Ok(("clients.csv ({0} lignes, separateur ';', UTF-8 BOM)" -f ($clients.Count - 1)))

    # --- Version "apres migration" : pour tester Compare-DataFiles KeyedRows ---
    $clients2 = New-Object 'System.Collections.Generic.List[string]'
    $clients2.Add('CODE_CLIENT;RAISON_SOCIALE;VILLE;REGION;MONTANT;DATE_CREATION;STATUT')
    for ($j = 1; $j -le 200; $j++) {
        if ($j % 25 -eq 0) { continue }                       # lignes SUPPRIMEES
        $statut = if ($j % 11 -eq 0) { 'Invalide' } else { 'Valide' }
        $mnt = if ($j % 13 -eq 0) { '{0:N2}' -f ($j * 200.00) } else { '{0:N2}' -f ($j * 137.45) }  # MODIFIEES
        $ville = if ($j % 31 -eq 0) { 'Toulouse' } else { $villes[$j % 6] }                          # MODIFIEES
        $clients2.Add(('CLI{0:D4};{1} {2};{3};{4};{5};2026-0{6}-1{7};{8}' -f
            $j, $societes[$j % 6], $j, $ville, $regions[$j % 6], $mnt, (($j % 9) + 1), ($j % 9), $statut))
    }
    for ($j = 201; $j -le 215; $j++) {                        # lignes AJOUTEES
        $clients2.Add(('CLI{0:D4};Nouvelle Societe {1};Strasbourg;Grand Est;{2:N2};2026-08-20;Valide' -f $j, $j, ($j * 100.0)))
    }
    [EcrivainTexte]::EcrireUtf8AvecBom((Join-Path $dCsv 'clients_apres_migration.csv'), $clients2)
    $journal.Ok('clients_apres_migration.csv (8 supprimees, ~21 modifiees, 15 ajoutees)')

    # --- Ventes : virgule comme separateur ---
    $ventes = New-Object 'System.Collections.Generic.List[string]'
    $ventes.Add('ID_VENTE,CODE_CLIENT,CODE_PRODUIT,QUANTITE,PRIX_UNITAIRE,DATE_VENTE')
    for ($j = 1; $j -le 500; $j++) {
        $ventes.Add(('V{0:D6},CLI{1:D4},PRD{2:D3},{3},{4}.{5:D2},2026-0{6}-{7:D2}' -f
            $j, (($j % 200) + 1), (($j % 40) + 1), (($j % 9) + 1), (($j * 7) % 500 + 10), ($j % 100), (($j % 8) + 1), (($j % 28) + 1)))
    }
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dCsv 'ventes.csv'), $ventes)
    $journal.Ok("ventes.csv (500 lignes, separateur ',')")

    # --- Referentiel produits : TABULATION comme separateur ---
    $produits = New-Object 'System.Collections.Generic.List[string]'
    $produits.Add("CODE_PRODUIT`tLIBELLE`tFAMILLE`tPRIX_CATALOGUE")
    $familles = @('Assurance Vie', 'Prevoyance', 'Retraite', 'Sante')
    for ($j = 1; $j -le 40; $j++) {
        if ($j -eq 17) { continue }                # code manquant : test de jointure incomplete
        $produits.Add(("PRD{0:D3}`tProduit {1}`t{2}`t{3:N2}" -f $j, $j, $familles[$j % 4], ($j * 49.9)))
    }
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dCsv 'produits.tsv'), $produits)
    $journal.Ok('produits.tsv (39 lignes, separateur TAB, PRD017 volontairement absent)')

    # --- Ancien export en ANSI : test de conversion d'encodage ---
    # Caracteres accentues construits par CODE UNICODE EXPLICITE plutot
    # qu'ecrits litteralement dans le source : ce fichier .ps1 n'a pas de
    # BOM, or Windows PowerShell 5.1 lit un .ps1 sans BOM avec l'encodage
    # ANSI du systeme (pas UTF-8). Un accent tape directement dans le code
    # source serait donc mal decode des la lecture du script lui-meme,
    # rendant ce fixture de test ANSI indetectable comme tel - c'est
    # exactement le bug observe et diagnostique en test.
    $e  = [char]0x00E9   # e aigu (Societe, Generale, echeance, fevrier...)
    $eg = [char]0x00E8   # e grave (Reglement)
    $a  = [char]0x00E0   # a grave (a)
    $o  = [char]0x00F4   # o circonflexe (Cote)
    $c  = [char]0x00E7   # c cedille (Provencale)

    $ansi = @(
        'CODE;LIBELLE;COMMENTAIRE',
        ('REF001;Soci{0}t{0} G{0}n{0}rale;R{1}glement {2} {0}ch{0}ance du 15 f{0}vrier' -f $e, $eg, $a),
        ('REF002;Cabinet H{0}risson;Dossier {1} compl{0}ter avant le d{0}lai' -f $e, $a),
        ('REF003;Etablissements C{0}te d''Azur;R{1}glement {2}chelonn{2}' -f $o, $eg, $e),
        ('REF004;Maison Proven{0}ale;Cr{1}ance r{1}siduelle non sold{1}e' -f $c, $e)
    )
    [EcrivainTexte]::EcrireAnsi((Join-Path $dCsv 'export_ancien_ansi.csv'), $ansi)
    $journal.Ok('export_ancien_ansi.csv (encodage ANSI, a convertir)')

    # --- Exports quotidiens : test de fusion ---
    $dQuot = Join-Path $dCsv 'quotidien'
    New-Item -Path $dQuot -ItemType Directory -Force | Out-Null
    for ($jour = 1; $jour -le 5; $jour++) {
        $q = New-Object 'System.Collections.Generic.List[string]'
        $q.Add('DATE_OPERATION;COMPTE;MONTANT;SENS')
        for ($k = 1; $k -le 50; $k++) {
            $sens = if ($k % 2 -eq 0) { 'CREDIT' } else { 'DEBIT' }
            $q.Add(('2026-08-0{0};CPT{1:D5};{2:N2};{3}' -f $jour, (($k * $jour) % 999), ($k * 31.7 * $jour), $sens))
        }
        [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dQuot ('operations_2026080{0}.csv' -f $jour)), $q)
    }
    $journal.Ok('quotidien/ : 5 fichiers de 50 lignes (test de fusion)')

    # --- Liste de filtrage : test "filtrer un tableau a partir d'une liste" ---
    $filtre = @('CLI0003', 'CLI0007', 'CLI0015', 'CLI0042', 'CLI0088', 'CLI0100',
                'CLI0155', 'CLI0199', 'CLI9999')
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dCsv 'liste_clients_a_extraire.txt'), $filtre)
    $journal.Ok('liste_clients_a_extraire.txt (9 codes dont 1 inexistant)')

    $journal.FinEtape()


    # ======================================================================
    $journal.Etape('03_XML_JSON - configuration et referentiels')

    $tablesJson = @'
{
  "kpa_parties":        ["name", "first_name", "particule", "maiden_name", "marital_status", "party_id"],
  "kpa_addresses":      ["line0", "line1", "line2", "line3", "zip_code", "city"],
  "kpa_bank_accounts":  ["account_number", "account_holder", "iban_account", "bic_code"],
  "kpa_organizations":  ["banner", "siret_code", "remarks"],
  "kpa_persons":        ["maiden_name", "marital_status"],
  "kpa_party_contacts": ["contact_name", "contact_email"],
  "kcm_pol_beneficiaries": ["benef_name", "benef_first_name", "rank"],
  "kcm_pol_benef_clause":  ["death_clause_text"],
  "kcf_payments":       ["bank_account", "amount"],
  "kcf_treasury_account_group": ["comment_text"]
}
'@
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dXml 'tables.json'), @($tablesJson))
    $journal.Ok('tables.json (10 tables, 33 colonnes)')

    # Variante INVALIDE : virgule en trop -> test du message d'erreur JSON
    $tablesKo = @'
{
  "kpa_parties": ["name", "first_name",],
  "kpa_addresses": ["line0"]
}
'@
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dXml 'tables_INVALIDE.json'), @($tablesKo))
    $journal.Attention('tables_INVALIDE.json (JSON volontairement errone, pour tester le diagnostic)')

    $xml = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<referentiel>',
        '  <parametres>',
        '    <parametre nom="serveur" valeur="SRVSQL01" />',
        '    <parametre nom="base" valeur="DWH_PROD" />',
        '    <parametre nom="timeout" valeur="300" />',
        '  </parametres>',
        '  <tables>'
    )
    $xmlListe = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $xml) { $xmlListe.Add($l) }
    $tablesXml = @('kpa_parties', 'kpa_addresses', 'kpa_bank_accounts', 'kpa_organizations')
    foreach ($t in $tablesXml) {
        $xmlListe.Add(('    <table nom="{0}" schema="dbo" active="true" />' -f $t))
    }
    $xmlListe.Add('  </tables>')
    $xmlListe.Add('</referentiel>')
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dXml 'referentiel.xml'), $xmlListe)
    $journal.Ok('referentiel.xml')

    $journal.FinEtape()


    # ======================================================================
    $journal.Etape('05_SQL - script SQL Server')

    $sql = @(
        '-- ============================================================',
        '-- Jeu de donnees de test pour SQL Server',
        '-- A executer dans une base de developpement (PAS en production)',
        '-- ============================================================',
        '',
        'IF OBJECT_ID(''dbo.Staging_Clients'', ''U'') IS NOT NULL DROP TABLE dbo.Staging_Clients;',
        'GO',
        'CREATE TABLE dbo.Staging_Clients (',
        '    CODE_CLIENT     VARCHAR(20)   NOT NULL,',
        '    RAISON_SOCIALE  VARCHAR(200)  NULL,',
        '    VILLE           VARCHAR(100)  NULL,',
        '    REGION          VARCHAR(100)  NULL,',
        '    MONTANT         DECIMAL(18,2) NULL,',
        '    DATE_CREATION   DATE          NULL,',
        '    STATUT          VARCHAR(20)   NULL,',
        '    DATE_CHARGEMENT DATETIME      DEFAULT GETDATE()',
        ');',
        'GO',
        '',
        '-- Table de controle : sert a tester Invoke-SqlQuery et Get-SqlTableSchema',
        'IF OBJECT_ID(''dbo.Ref_Produits'', ''U'') IS NOT NULL DROP TABLE dbo.Ref_Produits;',
        'GO',
        'CREATE TABLE dbo.Ref_Produits (',
        '    CODE_PRODUIT    VARCHAR(20)  NOT NULL PRIMARY KEY,',
        '    LIBELLE         VARCHAR(200) NULL,',
        '    FAMILLE         VARCHAR(100) NULL,',
        '    PRIX_CATALOGUE  DECIMAL(18,2) NULL',
        ');',
        'GO',
        '',
        'INSERT INTO dbo.Ref_Produits (CODE_PRODUIT, LIBELLE, FAMILLE, PRIX_CATALOGUE) VALUES',
        "('PRD001', 'Produit 1', 'Assurance Vie', 49.90),",
        "('PRD002', 'Produit 2', 'Prevoyance',    99.80),",
        "('PRD003', 'Produit 3', 'Retraite',     149.70),",
        "('PRD004', 'Produit 4', 'Sante',        199.60);",
        'GO',
        '',
        '-- Requetes de controle de coherence (usage quotidien type)',
        '-- 1. Doublons sur la cle',
        'SELECT CODE_CLIENT, COUNT(*) AS NB',
        'FROM dbo.Staging_Clients GROUP BY CODE_CLIENT HAVING COUNT(*) > 1;',
        '',
        '-- 2. Valeurs orphelines (pas de correspondance dans le referentiel)',
        'SELECT DISTINCT v.CODE_PRODUIT',
        'FROM dbo.Staging_Ventes v',
        'LEFT JOIN dbo.Ref_Produits p ON p.CODE_PRODUIT = v.CODE_PRODUIT',
        'WHERE p.CODE_PRODUIT IS NULL;',
        '',
        '-- 3. Taux de remplissage par colonne',
        'SELECT COUNT(*) AS TOTAL,',
        '       SUM(CASE WHEN RAISON_SOCIALE IS NULL THEN 1 ELSE 0 END) AS RS_VIDES,',
        '       SUM(CASE WHEN MONTANT IS NULL THEN 1 ELSE 0 END)        AS MT_VIDES',
        'FROM dbo.Staging_Clients;'
    )
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $dSql 'creation_jeu_test.sql'), $sql)
    $journal.Ok('creation_jeu_test.sql')

    $journal.FinEtape()


    # ======================================================================
    if (-not $NoExcel) {
        $journal.Etape('04_EXCEL - classeurs multi-feuilles')

        # ---------------- CRE.xlsx ----------------
        $ctor = $null
        try {
            $ctor = [ConstructeurExcel]::new($journal)

            # --- Feuille 1-CRE ---
            $f1 = New-Object 'System.Collections.Generic.List[object]'
            $f1.Add(@('TOPIC', 'CRE_ID', 'CRE', 'TYPE_CRE', 'TYPE_CRE_MOD', 'CRE_STATUS', 'REQUEST'))

            $definitionsCre = @(
                @('Tiers',   '160', 'CRE_PARTIES',              'kpa_parties',      'NAME, FIRST_NAME, PARTICULE'),
                @('Tiers',   '163', 'CRE_PARTIES_MEDIUM',       'kpa_parties',      'NAME, FIRST_NAME, PARTICULE'),
                @('Tiers',   '167', 'CRE_PERSONS',              'kpa_persons',      'MAIDEN_NAME, MARITAL_STATUS'),
                @('Adresse', '146', 'CRE_ADDRESSES',            'kpa_addresses',    'LINE0, LINE1, LINE2, LINE3'),
                @('Adresse', '148', 'CRE_PARTY_ADDRESSES',      'kpa_addresses',    'LINE0, ZIP_CODE, CITY'),
                @('Banque',  '150', 'CRE_BANK_ACCOUNTS',        'kpa_bank_accounts','ACCOUNT_NUMBER, ACCOUNT_HOLDER, IBAN_ACCOUNT'),
                @('Banque',  '151', 'CRE_PARTY_BANK_ACCOUNTS',  'kpa_bank_accounts','ACCOUNT_NUMBER, ACCOUNT_HOLDER'),
                @('Societe', '157', 'CRE_ORGANIZATIONS',        'kpa_organizations','BANNER, SIRET_CODE, REMARKS'),
                @('Contrat', '024', 'CRE_POLICY_BENEFICIARIES', 'kcm_pol_beneficiaries', 'BENEF_NAME, BENEF_FIRST_NAME'),
                @('Contrat', '022', 'CRE_POLICY_BENEF_CLAUSE',  'kcm_pol_benef_clause',  'DEATH_CLAUSE_TEXT'),
                @('Paiement','152', 'CRE_PAYMENTS',             'kcf_payments',     'BANK_ACCOUNT, AMOUNT'),
                @('Tresor',  '160', 'CRE_TREASURY_ACCOUNT_GROUP','kcf_treasury_account_group', 'COMMENT_TEXT'),
                @('Contact', '169', 'CRE_PARTY_CONTACTS',       'kpa_party_contacts','CONTACT_NAME, CONTACT_EMAIL'),
                @('Fonds',   '141', 'CRE_FUNDS',                'kpa_parties',      'NAME'),
                @('Divers',  '999', 'CRE_SANS_TABLE_CIBLEE',    'table_inconnue',   'CHAMP_A, CHAMP_B')
            )

            foreach ($d in $definitionsCre) {
                $topic = $d[0]; $id = $d[1]; $cre = $d[2]; $tbl = $d[3]; $cols = $d[4]
                $alias = ($tbl.Substring(0, 3)).ToUpperInvariant()
                $listeCols = ($cols -split ',\s*' | ForEach-Object { "{0}.{1}" -f $alias, $_ }) -join ', '
                $requete = "SELECT {0} FROM {1} {2} WHERE {2}.STATUS = 1" -f $listeCols, $tbl, $alias

                # Chaque CRE existe en version Complet ET Differentiel
                $f1.Add(@($topic, $id, $cre, 'Complet',      'CRE Complet (sans date de depart)', 'Valide',   $requete))
                $f1.Add(@($topic, $id, $cre, 'Differentiel', 'CRE Delta (CRE Pilots)',            'Valide',   ("{0} AND {1}.MODIFICATION_DATE > :DATE_DEB" -f $requete, $alias)))
            }
            # Cas a exclure par les filtres
            $f1.Add(@('Divers', '900', 'CRE_INVALIDE_TEST', 'Differentiel', 'CRE Delta (CRE Pilots)', 'Invalide', 'SELECT KPA.NAME FROM kpa_parties KPA'))
            $f1.Add(@('Divers', '901', 'CRE_SANS_REQUETE',  'Differentiel', 'CRE Delta (CRE Pilots)', 'Valide',   ''))

            $ctor.AjouterFeuille('1-CRE', $f1.ToArray())

            # --- Feuille Tables (catalogue de colonnes) ---
            $f2 = New-Object 'System.Collections.Generic.List[object]'
            $f2.Add(@('tABLE_NAME', 'COLUMN_ID', 'COLUMN_NAME', 'DATA_TYPE', 'DATA_LENGTH'))
            $catalogue = @{
                'KPA_PARTIES'        = @('PARTY_ID', 'NAME', 'FIRST_NAME', 'PARTICULE', 'MAIDEN_NAME', 'MARITAL_STATUS', 'STATUS')
                'KPA_ADDRESSES'      = @('ADDRESS_ID', 'LINE0', 'LINE1', 'LINE2', 'LINE3', 'ZIP_CODE', 'CITY')
                'KPA_BANK_ACCOUNTS'  = @('BANK_ACCOUNT_ID', 'ACCOUNT_NUMBER', 'ACCOUNT_HOLDER', 'IBAN_ACCOUNT', 'BIC_CODE')
                'KPA_ORGANIZATIONS'  = @('ORG_ID', 'BANNER', 'SIRET_CODE', 'REMARKS')
                'KCM_POL_BENEFICIARIES' = @('BENEF_ID', 'BENEF_NAME', 'BENEF_FIRST_NAME', 'RANK')
            }
            foreach ($t in ($catalogue.Keys | Sort-Object)) {
                $i = 0
                foreach ($c in $catalogue[$t]) {
                    $i = $i + 1
                    $type = if ($c -like '*_ID' -or $c -eq 'STATUS' -or $c -eq 'RANK') { 'NUMBER' } else { 'VARCHAR2' }
                    $len  = if ($type -eq 'NUMBER') { 22 } else { 200 }
                    $f2.Add(@($t, $i, $c, $type, $len))
                }
            }
            $ctor.AjouterFeuille('Tables', $f2.ToArray())

            # --- Feuille MAPPING_CRE (produite par Extract-CreTableColumns) ---
            $f3 = New-Object 'System.Collections.Generic.List[object]'
            $f3.Add(@('CRE', 'TABLE', 'COLONNES'))
            foreach ($d in $definitionsCre) {
                if ($d[3] -eq 'table_inconnue') { continue }
                foreach ($c in ($d[4] -split ',\s*')) {
                    $f3.Add(@($d[2], $d[3], $c.ToLowerInvariant()))
                }
            }
            # Cas limites pour Resolve-CreViewAliases
            $f3.Add(@('CRE_CRE_ABSENT_DE_BASE', 'kpa_parties', 'name'))
            $f3.Add(@('CRE_PARTIES', 'kpa_parties', 'colonne_qui_nexiste_pas'))
            $ctor.AjouterFeuille('MAPPING_CRE', $f3.ToArray())

            # --- Feuille CRE_DISTINCTS (liste simple) ---
            $f4 = New-Object 'System.Collections.Generic.List[object]'
            $f4.Add(@('CRE'))
            $vus = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($d in $definitionsCre) {
                if ($vus.Add($d[2])) { $f4.Add(@($d[2])) }
            }
            $ctor.AjouterFeuille('CRE_DISTINCTS', $f4.ToArray())

            $ctor.Enregistrer((Join-Path $dExcel 'CRE.xlsx'))
        }
        finally {
            if ($ctor) { $ctor.Fermer() }
        }

        # ---------------- base.xlsx ----------------
        $ctor2 = $null
        try {
            $ctor2 = [ConstructeurExcel]::new($journal)

            # --- Feuille PERIMETRE CRE ---
            $b1 = New-Object 'System.Collections.Generic.List[object]'
            $b1.Add(@('CRE', 'CRE_CSV', 'REQUETE'))
            foreach ($d in $definitionsCre) {
                $b1.Add(@($d[2], ("{0}_csv" -f $d[2]),
                          ("SELECT '{0}_csv' as CRE_NAME UNION" -f $d[2])))
            }
            $ctor2.AjouterFeuille('PERIMETRE CRE', $b1.ToArray())

            # --- Feuille RESULTAT 1 : CRE_csv -> VIEW_NAME / TABLE_TFT ---
            # Correspondances construites pour que les alias SOIENT trouvables
            # dans vues.txt, avec quelques cas volontairement absents.
            $b2 = New-Object 'System.Collections.Generic.List[object]'
            $b2.Add(@('CRE', 'DERNIER_IMPORT', 'VIEW_NAME', 'SchemaName', 'TABLE_TFT'))

            $correspondances = @(
                @('CRE_PARTIES',              'V_TFT_K_TIERS',                'TFT_K_TIERS'),
                @('CRE_PARTIES',              'V_TFT_K_TIERS_1',              'TFT_K_TIERS'),
                @('CRE_PARTIES_MEDIUM',       'V_TFT_K_TIERS_1',              'TFT_K_TIERS'),
                @('CRE_PARTIES_MEDIUM',       'V_TFT_K_TIERS_2',              'TFT_K_TIERS'),
                @('CRE_PERSONS',              'V_TFT_K_TIERS',                'TFT_K_TIERS'),
                @('CRE_ADDRESSES',            'V_TFT_K_ADRESSES',             'TFT_K_ADRESSES'),
                @('CRE_ADDRESSES',            'V_TFT_K_ADRESSES_VALIDES',     'TFT_K_ADRESSES'),
                @('CRE_PARTY_ADDRESSES',      'V_TFT_K_ADRESSES',             'TFT_K_ADRESSES'),
                @('CRE_BANK_ACCOUNTS',        'V_TFT_K_RIB_KELIA',            'TFT_K_RIB_KELIA'),
                @('CRE_PARTY_BANK_ACCOUNTS',  'V_TFT_K_COORDONNEES_BANCAIRES','TFT_K_COORDONNEES_BANCAIRES'),
                @('CRE_ORGANIZATIONS',        'V_TFT_K_TIERS_2',              'TFT_K_TIERS'),
                @('CRE_POLICY_BENEFICIARIES', 'V_TFT_K_BENEFICIAIRES_CONTRAT','TFT_K_BENEFICIAIRES'),
                @('CRE_POLICY_BENEF_CLAUSE',  'V_TFT_K_CLAUSES_BENEFICIAIRES','TFT_K_CLAUSES_BENEFICIAIRES'),
                @('CRE_PAYMENTS',             'V_TFT_K_DECAISSEMENTS',        'TFT_K_DECAISSEMENTS'),
                @('CRE_TREASURY_ACCOUNT_GROUP','V_TFT_K_REGROUPEMENTS_COMPTES_TRESORERIE','TFT_K_REGROUPEMENTS_COMPTES_TRESORERIE'),
                @('CRE_PARTY_CONTACTS',       'V_TFT_K_CONTACTS',             'TFT_K_CONTACTS'),
                @('CRE_FUNDS',                'V_TFT_K_PLACES_COTATION',      'TFT_K_SUPPORTS'),
                # Vue citee mais ABSENTE de vues.txt -> doit etre signalee
                @('CRE_FUNDS',                'V_TFT_K_VUE_NON_DEFINIE',      'TFT_K_SUPPORTS')
            )

            $h = 0
            foreach ($c in $correspondances) {
                $h = $h + 1
                $b2.Add(@(("{0}_csv" -f $c[0]),
                          ('2026-08-12 0{0}:{1:D2}:00' -f (($h % 9)), (($h * 7) % 60)),
                          $c[1], 'dbo', $c[2]))
            }
            $ctor2.AjouterFeuille('RESULTAT 1', $b2.ToArray())

            $ctor2.Enregistrer((Join-Path $dExcel 'base.xlsx'))
        }
        finally {
            if ($ctor2) { $ctor2.Fermer() }
        }

        # ---------------- donnees_croisement.xlsx ----------------
        # Sert a tester : filtrage par liste, doublons, croisement de feuilles
        $ctor3 = $null
        try {
            $ctor3 = [ConstructeurExcel]::new($journal)

            $c1 = New-Object 'System.Collections.Generic.List[object]'
            $c1.Add(@('CODE_CLIENT', 'RAISON_SOCIALE', 'VILLE', 'MONTANT', 'STATUT'))
            for ($j = 1; $j -le 120; $j++) {
                $st = if ($j % 11 -eq 0) { 'Invalide' } else { 'Valide' }
                $c1.Add(@(('CLI{0:D4}' -f $j), ("{0} {1}" -f $societes[$j % 6], $j),
                          $villes[$j % 6], ($j * 137.45), $st))
            }
            # Doublons volontaires
            $c1.Add(@('CLI0007', 'Doublon volontaire', 'Paris', 961.15, 'Valide'))
            $c1.Add(@('CLI0042', 'Doublon volontaire', 'Lyon', 5772.90, 'Valide'))
            $ctor3.AjouterFeuille('DONNEES', $c1.ToArray())

            $c2 = New-Object 'System.Collections.Generic.List[object]'
            $c2.Add(@('CODE_CLIENT'))
            foreach ($code in @('CLI0003','CLI0007','CLI0015','CLI0042','CLI0088','CLI0100','CLI0119','CLI9999')) {
                $c2.Add(@($code))
            }
            $ctor3.AjouterFeuille('LISTE_A_EXTRAIRE', $c2.ToArray())

            $c3 = New-Object 'System.Collections.Generic.List[object]'
            $c3.Add(@('CODE_CLIENT', 'SEGMENT', 'CHARGE_AFFAIRES'))
            for ($j = 1; $j -le 100; $j = $j + 2) {
                $seg = @('Grand Compte', 'PME', 'Particulier')[$j % 3]
                $c3.Add(@(('CLI{0:D4}' -f $j), $seg, ('CA{0:D2}' -f ($j % 12))))
            }
            $ctor3.AjouterFeuille('REFERENTIEL', $c3.ToArray())

            $ctor3.Enregistrer((Join-Path $dExcel 'donnees_croisement.xlsx'))
        }
        finally {
            if ($ctor3) { $ctor3.Fermer() }
        }

        $journal.FinEtape()
    }
    else {
        $journal.Attention('Generation Excel ignoree (-NoExcel)')
    }


    # ======================================================================
    $journal.Etape('Redaction du LISEZMOI')

    $lisezmoi = @(
        '================================================================================',
        ' LABORATOIRE DE TEST ETL - INVENTAIRE',
        ('  Genere le {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        '================================================================================',
        '',
        'ARBORESCENCE',
        '------------',
        '  01_TEXTE/',
        '     vues.txt                      14 definitions CREATE VIEW (cas pieges inclus)',
        '     vues_v2.txt                   idem + 1 alias modifie + 1 vue ajoutee',
        '     liste_A.txt / liste_B.txt     listes a rapprocher (doublons, casse, vide)',
        '     traitement.log                300 lignes de journal avec erreurs ORA-*',
        '     export_largeur_fixe.txt       40 lignes a largeur fixe',
        '',
        '  02_CSV/',
        '     clients.csv                   204 lignes, separateur '';'', UTF-8 BOM, accents',
        '     clients_apres_migration.csv   version modifiee (ajouts/suppressions/modifs)',
        '     ventes.csv                    500 lignes, separateur '',''',
        '     produits.tsv                  39 lignes, separateur TAB (PRD017 absent)',
        '     export_ancien_ansi.csv        encodage ANSI a convertir',
        '     liste_clients_a_extraire.txt  9 codes pour test de filtrage',
        '     quotidien/                    5 fichiers a fusionner',
        '',
        '  03_XML_JSON/',
        '     tables.json                   10 tables / 33 colonnes (valide)',
        '     tables_INVALIDE.json          JSON errone (test du diagnostic)',
        '     referentiel.xml               parametres et liste de tables',
        '',
        '  04_EXCEL/',
        '     CRE.xlsx                      feuilles : 1-CRE, Tables, MAPPING_CRE, CRE_DISTINCTS',
        '     base.xlsx                     feuilles : PERIMETRE CRE, RESULTAT 1',
        '     donnees_croisement.xlsx       feuilles : DONNEES, LISTE_A_EXTRAIRE, REFERENTIEL',
        '',
        '  05_SQL/',
        '     creation_jeu_test.sql         tables + requetes de controle',
        '',
        '  99_SORTIES/                      dossier vide, destine aux resultats',
        '',
        '',
        'ANOMALIES VOLONTAIREMENT INTRODUITES',
        '------------------------------------',
        '  * doublons        : CLI0007 et CLI0042 apparaissent deux fois',
        '  * casse           : "cre_parties" en minuscules dans liste_A.txt',
        '  * ligne vide      : derniere ligne de liste_A.txt',
        '  * valeur manquante: CLI9998 sans raison sociale',
        '  * format invalide : XXX123 (code non conforme), montant "abc", date "pas-une-date"',
        '  * montant negatif : CLI9998 a -500,00',
        '  * jointure trouee : PRD017 absent du referentiel produits',
        '  * CRE orphelin    : CRE_CRE_ABSENT_DE_BASE dans MAPPING_CRE',
        '  * colonne absente : colonne_qui_nexiste_pas dans MAPPING_CRE',
        '  * vue non definie : V_TFT_K_VUE_NON_DEFINIE citee mais absente de vues.txt',
        '  * statut exclu    : CRE_INVALIDE_TEST (CRE_STATUS = Invalide)',
        '  * requete vide    : CRE_SANS_REQUETE',
        '  * JSON errone     : tables_INVALIDE.json',
        '  * encodage ANSI   : export_ancien_ansi.csv',
        '',
        'Ces anomalies sont NORMALES : elles servent a verifier que les utilitaires',
        'les detectent et les signalent correctement au lieu de planter.',
        '',
        '================================================================================',
        'Pour lancer les tests : .\Start-Toolkit.ps1  (menu interactif)',
        '================================================================================'
    )
    [EcrivainTexte]::EcrireUtf8SansBom((Join-Path $Path 'LISEZMOI.txt'), $lisezmoi)
    $journal.Ok('LISEZMOI.txt')
    $journal.FinEtape()


    # ======================================================================
    $journal.Ecrire(('-' * 78), 'DarkGray')
    $journal.Ecrire('BILAN', 'Cyan')

    $fichiers = Get-ChildItem -LiteralPath $Path -Recurse -File
    $totalMo = ($fichiers | Measure-Object -Property Length -Sum).Sum / 1MB

    $journal.Ecrire(("Dossier cree      : {0}" -f $Path), 'White')
    $journal.Ecrire(("Fichiers generes  : {0}" -f $fichiers.Count), 'White')
    $journal.Ecrire(("Taille totale     : {0:N2} Mo" -f $totalMo), 'White')
    $journal.Ecrire(("Duree             : {0}" -f $journal.Duree()), 'White')
    $journal.Ecrire(('=' * 78), 'DarkGray')
    $journal.Ecrire('LABORATOIRE PRET', 'Green')
    $journal.Ecrire('', 'White')
    $journal.Ecrire(("Consultez {0}\LISEZMOI.txt pour l'inventaire complet." -f $Path), 'Cyan')
}
catch {
    $journal.Ecrire('', 'White')
    $journal.Ecrire(('#' * 78), 'Red')
    $journal.Ecrire('#  ERREUR', 'Red')
    $journal.Ecrire(('#' * 78), 'Red')
    $journal.Ecrire(("#  MESSAGE     : {0}" -f $_.Exception.Message), 'Red')
    if ($_.InvocationInfo) {
        $journal.Ecrire(("#  LIGNE       : {0}" -f $_.InvocationInfo.ScriptLineNumber), 'Red')
        if ($_.InvocationInfo.Line) {
            $journal.Ecrire(("#  CODE FAUTIF : {0}" -f $_.InvocationInfo.Line.Trim()), 'Yellow')
        }
    }
    $journal.Ecrire(("#  TYPE .NET   : {0}" -f $_.Exception.GetType().FullName), 'Red')
    if ($_.ScriptStackTrace) {
        foreach ($l in ($_.ScriptStackTrace -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($l)) {
                $journal.Ecrire(("#    {0}" -f $l.Trim()), 'DarkGray')
            }
        }
    }
    $journal.Ecrire(('#' * 78), 'Red')
    exit 1
}
