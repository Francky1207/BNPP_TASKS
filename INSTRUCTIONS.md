# Instructions — Débogage, traçage et résolution des alias de vues

Consolidation des consignes fournies pour les trois sujets traités :
connaître sa version de PowerShell, tracer et déboguer efficacement,
et exécuter le script d'enrichissement de `MAPPING_CRE`.

---

## Table des matières

1. [Connaître sa version de PowerShell](#1-connaître-sa-version-de-powershell)
2. [Le module de traçage `PSToolkit-Trace.psm1`](#2-le-module-de-traçage-pstoolkit-tracepsm1)
3. [Couverture du traitement précédent](#3-couverture-du-traitement-précédent)
4. [Le script `Resolve-CreViewAliases.ps1`](#4-le-script-resolve-creviewaliasesps1)
5. [Validation de la logique d'analyse SQL](#5-validation-de-la-logique-danalyse-sql)
6. [Récapitulatif des fichiers](#6-récapitulatif-des-fichiers)

---

## 1. Connaître sa version de PowerShell

Commande minimale :

```powershell
$PSVersionTable.PSVersion
```

Version complète (édition, support des classes, politique d'exécution, droits admin) :

```powershell
Import-Module "C:\CRE\PSToolkit-Trace.psm1" -Force
Get-PowerShellInfo
```

Cette fonction renvoie notamment :

| Propriété | Intérêt |
|---|---|
| `Version` / `VersionMajeure` | 5.1 ou 7.x |
| `Edition` | Desktop (5.1) ou Core (7+) |
| `SupporteLesClasses` | vrai à partir de la version 5 |
| `SupporteTernaire` | vrai à partir de la version 7 |
| `EstAdministrateur` | confirme que rien n'exige l'élévation |
| `PolitiqueExecution` | RemoteSigned, AllSigned, Bypass… |
| `Culture` | important pour l'analyse des nombres et dates |

---

## 2. Le module de traçage `PSToolkit-Trace.psm1`

### Ce qu'il apporte

`Write-Log` seul ne suffisait pas. Ce module produit **automatiquement, à chaque erreur** :

- l'**étape** en cours (où on en était)
- la **fonction** fautive
- le **fichier**, la **ligne** et la **colonne** exacts
- la **ligne de code** en cause
- le **type .NET** de l'exception
- la **chaîne d'exceptions internes** — la cause racine est souvent la dernière
- la **pile d'appel** complète
- le **contexte métier** fourni (quel fichier, quelle ligne de données)

### Utilisation minimale

```powershell
Import-Module "C:\CRE\PSToolkit-Trace.psm1" -Force

Start-Trace -LogPath "C:\CRE\logs\run.log"

$data = Invoke-Step -Name 'Lecture Excel' -Action {
    Import-ExcelSheet -Path "C:\CRE\CRE.xlsx" -SheetName 'CRE'
}

Stop-Trace -ExportErrorsTo "C:\CRE\logs\erreurs.csv"
```

### Fonctionnalités complémentaires

**Étapes imbriquées** — l'indentation du log montre immédiatement à quel niveau ça a cassé.

**Collecte de plusieurs erreurs** — `-ContinueOnError` permet de traiter une boucle
entièrement et de récupérer toutes les erreurs à la fin, au lieu de s'arrêter à la première :

```powershell
foreach ($f in $fichiers) {
    Invoke-Step -Name ("Traitement {0}" -f $f.Name) -ContinueOnError `
        -Context @{ Fichier = $f.FullName; Taille = $f.Length } -Action {
            Import-Csv $f.FullName
        }
}

Get-TraceError | Format-Table Etape, Fonction, Ligne, Message -AutoSize
```

**Échouer tôt avec un message clair** plutôt que tard avec une erreur incompréhensible :

```powershell
Assert-Condition -Condition (Test-Path $f) `
                 -Message "Fichier source introuvable" `
                 -Context @{ Chemin = $f }
```

### Les 11 fonctions du module

`Start-Trace` · `Stop-Trace` · `Write-Step` · `Write-TraceLine` · `Invoke-Step` ·
`Get-ErrorReport` · `Show-ErrorReport` · `Assert-Condition` · `Format-Duration` ·
`Get-TraceError` · `Get-PowerShellInfo`

---

## 3. Couverture du traitement précédent

**Le toolkit ne reprend pas directement le traitement `tables.json` → `CRE.xlsx` → `MAPPING_CRE`.**

`Extract-CreTableColumns.ps1` reste un script autonome. `PSToolkit.psm1` fournit les
*briques* (`Import-ExcelSheet`, `Export-ExcelSheet`, `Read-TextFile`) mais pas la
logique métier d'analyse SQL propre à ce traitement.

Une réécriture unifiée (toolkit + traçage) est possible sur demande.

---

## 4. Le script `Resolve-CreViewAliases.ps1`

### Objectif

Enrichir `MAPPING_CRE` en ajoutant, pour chaque triplet (CRE, TABLE, COLONNE),
la vue SQL qui expose cette colonne et l'ALIAS sous lequel elle y apparaît.

### Chaîne de traitement

1. `CRE.xlsx` / `MAPPING_CRE` → lignes (CRE, TABLE, COLONNES)
2. `base.xlsx` → pour `CRE` + `_csv` : VIEW_NAME, TABLE_TFT
3. Fichier `.txt` des vues → définitions `CREATE VIEW ... AS SELECT ...`
4. Recherche de la colonne dans la liste SELECT de chaque vue candidate
5. **Seules les vues où la colonne est trouvée** sont conservées
6. Réécriture de `MAPPING_CRE` avec 5 colonnes supplémentaires

### Installation et exécution

Fichier **autonome** : aucune dépendance, un seul fichier à transférer via GitHub.

```powershell
cd C:\CRE
Unblock-File -Path "C:\CRE\Resolve-CreViewAliases.ps1"

.\Resolve-CreViewAliases.ps1 `
    -ExcelPath "C:\CRE\CRE.xlsx" `
    -BasePath  "C:\CRE\base.xlsx" `
    -ViewsPath "C:\CRE\vues.txt" `
    -LogPath   "C:\CRE\logs\run.log" `
    -CsvPath   "C:\CRE\resultat.csv"
```

### Recommandation : premier passage sans écriture

Inspectez le CSV **avant** toute modification de `CRE.xlsx` :

```powershell
.\Resolve-CreViewAliases.ps1 `
    -ExcelPath "C:\CRE\CRE.xlsx" `
    -BasePath  "C:\CRE\base.xlsx" `
    -ViewsPath "C:\CRE\vues.txt" `
    -CsvPath   "C:\CRE\resultat.csv" `
    -NoExcelOutput
```

Sinon, une sauvegarde automatique est créée dans `C:\CRE\_backup\` avant modification.

### Résultat dans MAPPING_CRE

Colonnes A-C inchangées, puis :

| Colonne | Contenu |
|---|---|
| D `VIEW_NAME` | Vue où la colonne a été trouvée |
| E `TABLE_TFT` | Table TFT associée (issue de base.xlsx) |
| F `ALIAS` | Nom exposé par la vue |
| G `EXPRESSION_SOURCE` | Expression SQL d'origine |
| H `STATUT` | Résultat du rapprochement |

**Une ligne par vue** où la colonne est trouvée. Les lignes sans correspondance sont
**conservées** avec un statut explicite plutôt que supprimées silencieusement :

| STATUT | Signification |
|---|---|
| `TROUVE` | Correspondance complète avec alias |
| `TROUVE_SANS_ALIAS` | Colonne trouvée mais sans alias dans la vue |
| `CRE_ABSENT_DE_BASE` | Le CRE (+`_csv`) n'existe pas dans base.xlsx |
| `COLONNE_NON_TROUVEE_DANS_LES_VUES` | Aucune vue candidate ne contient la colonne |
| `PAS_DE_COLONNE` | Ligne de mapping sans colonne renseignée |

### Paramètres disponibles

| Paramètre | Défaut | Rôle |
|---|---|---|
| `-ExcelPath` | *(obligatoire)* | Classeur contenant MAPPING_CRE |
| `-BasePath` | *(obligatoire)* | base.xlsx |
| `-ViewsPath` | *(obligatoire)* | Fichier .txt des CREATE VIEW |
| `-MappingSheet` | `MAPPING_CRE` | Feuille à enrichir |
| `-BaseSheet` | *(auto)* | Détection automatique par en-têtes |
| `-CreSuffix` | `_csv` | Suffixe ajouté dans base.xlsx |
| `-LogPath` | *(aucun)* | Fichier de log |
| `-CsvPath` | *(aucun)* | Export CSV supplémentaire |
| `-NoExcelOutput` | off | N'écrit pas dans le classeur |
| `-NoBackup` | off | Désactive la sauvegarde préventive |

### Débogage

Chaque étape est numérotée et chronométrée, en console et dans le log.
En cas d'erreur : étape, fonction, fichier, **ligne et colonne**, code fautif,
type .NET, exceptions internes et pile d'appel. **Une seule capture d'écran suffit
pour localiser le problème.**

### Deux points à surveiller au premier lancement

Le bilan de fin d'exécution les chiffre automatiquement :

1. **Nom réel de la feuille dans `base.xlsx`** — la détection est automatique par
   en-têtes (`RESULTAT 1` attendu). Si elle échoue, le message liste les feuilles
   disponibles ; utilisez alors `-BaseSheet "RESULTAT 1"`.
2. **Couverture du fichier `.txt`** — s'il ne contient pas toutes les vues citées
   dans `base.xlsx`, le compteur « Vues citées mais non définies » le signalera.

---

## 5. Validation de la logique d'analyse SQL

L'analyseur SQL a été testé sur la vue réelle `V_TFT_K_SUPPORTS_ACTE_GESTION`
avant livraison. Les cas délicats passent tous :

| Cas testé | Résultat |
|---|---|
| Alias explicite `TFT.STATUS AS STATUT` | alias = `STATUT` |
| Alias implicite `S.ID_SUPPORT` | alias = `ID_SUPPORT` |
| Virgules internes `DECODE(T.PARTICULE, 1, 'X', 0)` | non découpées à tort |
| **`TFT.FROM_DATE` vs mot-clé `FROM`** | non confondus — 12 colonnes détectées |
| Colonne absente | signalée `NON TROUVEE`, pas d'erreur |

Règles d'alias appliquées, dans l'ordre :

1. `EXPR AS ALIAS` → alias explicite
2. `TABLE.COLONNE` → `COLONNE` (alias implicite)
3. `COLONNE` → `COLONNE`
4. Sinon → vide (statut `TROUVE_SANS_ALIAS`)

---

## 6. Récapitulatif des fichiers

Tous à placer dans `C:\CRE\` :

| Fichier | Rôle |
|---|---|
| `Resolve-CreViewAliases.ps1` | Enrichissement de MAPPING_CRE (autonome) |
| `PSToolkit-Trace.psm1` | Traçage et diagnostic d'erreurs |
| `PSToolkit.psm1` | Bibliothèque de 42 fonctions ETL |
| `PSToolkit-Recettes.ps1` | 15 recettes prêtes à l'emploi |
| `FORMATION-POWERSHELL.md` | Cours complet en 20 chapitres |
| `Extract-CreTableColumns.ps1` | Traitement initial CRE → MAPPING_CRE |
| `tables.json` | Configuration tables/colonnes |

### Réflexe systématique après chaque récupération depuis GitHub

```powershell
Unblock-File -Path "C:\CRE\*.ps1"
Unblock-File -Path "C:\CRE\*.psm1"
```

### Validation JSON avant commit

Avant de committer une modification de `tables.json`, faites-la valider
(collage dans le chat, ou jsonlint.com depuis la tablette) — cela évite
un aller-retour GitHub complet pour une simple faute de syntaxe.
