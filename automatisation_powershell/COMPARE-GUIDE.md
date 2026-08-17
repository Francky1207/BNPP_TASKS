# Compare-DataFiles — Guide d'utilisation

Utilitaire universel de comparaison : deux fichiers, deux colonnes, deux versions.
Produit un rapport des différences **avec les numéros de ligne**.

**Autonome** : un seul fichier, aucune dépendance, aucun droit administrateur.

---

## Table des matières

1. [Comprendre l'architecture des fichiers livrés](#1-comprendre-larchitecture-des-fichiers-livrés)
2. [Les 5 modes de comparaison](#2-les-5-modes-de-comparaison)
3. [Installation](#3-installation)
4. [Cas d'usage courants](#4-cas-dusage-courants)
5. [Tous les paramètres](#5-tous-les-paramètres)
6. [Comprendre les statuts du rapport](#6-comprendre-les-statuts-du-rapport)
7. [Performance](#7-performance)
8. [Dépannage](#8-dépannage)

---

## 1. Comprendre l'architecture des fichiers livrés

Votre question était légitime : je ne l'avais pas clarifiée. Il existe **deux natures
de fichiers**, qui s'utilisent très différemment.

### A. Les SCRIPTS `.ps1` — autonomes, à exécuter

Ce sont des **programmes complets**. On les lance, ils font le travail, ils s'arrêtent.
Ils n'ont besoin de rien d'autre.

| Script | Ce qu'il fait |
|---|---|
| `Extract-CreTableColumns.ps1` | CRE.xlsx + tables.json → feuille MAPPING_CRE |
| `Resolve-CreViewAliases.ps1` | MAPPING_CRE + base.xlsx + vues.txt → alias |
| `Compare-DataFiles.ps1` | Compare deux sources → rapport de différences |

```powershell
.\Compare-DataFiles.ps1 -Path1 a.csv -Path2 b.csv -OutputPath diff.csv
```

**C'est tout.** Pas d'`Import-Module`, pas de préparation. Chacun embarque son propre
traçage, sa propre gestion d'erreur, sa propre lecture Excel.

### B. Les MODULES `.psm1` — des boîtes à outils, à importer

Ce sont des **bibliothèques de fonctions**. On ne les « lance » pas : on les charge
en mémoire, puis on appelle leurs fonctions dans *ses propres* scripts.

| Module | Contenu |
|---|---|
| `PSToolkit.psm1` | 42 fonctions ETL (CSV, Excel, SQL, fichiers, qualité) |
| `PSToolkit-Trace.psm1` | 11 fonctions de traçage et diagnostic |

```powershell
Import-Module "C:\CRE\PSToolkit.psm1" -Force        # charge les 42 fonctions
Import-Module "C:\CRE\PSToolkit-Trace.psm1" -Force  # charge le traçage

# maintenant leurs fonctions sont disponibles
Import-ExcelSheet -Path "C:\CRE\CRE.xlsx" -SheetName 'CRE'
```

C'est précisément l'erreur que vous avez rencontrée : `Import-ExcelSheet` appartient à
`PSToolkit.psm1`. Sans l'`Import-Module` correspondant, PowerShell ne connaît pas
cette commande.

### Quand utiliser quoi ?

| Situation | À utiliser |
|---|---|
| Une tâche récurrente et bien définie | Un **script** `.ps1` dédié |
| Écrire un nouveau traitement à vous | Les **modules**, comme briques |
| Vous découvrez PowerShell | Les scripts d'abord, les modules plus tard |

### Pourquoi `Compare-DataFiles.ps1` est autonome plutôt qu'ajouté au toolkit

C'est un choix délibéré, adapté à votre contrainte de transfert par GitHub :

- **Un seul fichier à transférer** au lieu de trois
- **Aucun risque d'oubli d'`Import-Module`** — la cause de votre dernière erreur
- **Aucune régression possible** sur le toolkit existant
- **Traçage identique** à `Resolve-CreViewAliases.ps1` : mêmes étapes numérotées,
  même rapport d'erreur détaillé

La duplication de code entre scripts est assumée : la fiabilité prime sur l'élégance
quand chaque bug coûte un aller-retour photo → GitHub → PC.

---

## 2. Les 5 modes de comparaison

| Mode | Question à laquelle il répond | Sources |
|---|---|---|
| `TextPositional` | La ligne 42 a-t-elle changé entre les deux versions ? | txt, log, sql, xml, json, csv |
| `TextSet` | Quelles lignes sont dans A mais pas dans B ? (ordre indifférent) | idem |
| `Columns` | Quelles valeurs de cette colonne manquent dans l'autre ? | Excel, CSV |
| `KeyedRows` | Pour la clé X, quels **champs** ont changé ? | Excel, CSV |
| `Auto` | Choisit tout seul selon les paramètres fournis | toutes |

### Comment choisir

- Deux **versions successives** d'un même fichier → `TextPositional`
- Deux **listes** à rapprocher, dans un ordre quelconque → `TextSet`
- Une **colonne** contre une autre (même fichier ou non) → `Columns`
- Un **contrôle de migration** avant/après → `KeyedRows`

---

## 3. Installation

Placez le fichier dans `C:\CRE\`, puis :

```powershell
Unblock-File -Path "C:\CRE\Compare-DataFiles.ps1"
```

Aucun module à importer, aucun droit particulier.

---

## 4. Cas d'usage courants

### 4.1 Deux fichiers texte, différences avec numéros de ligne

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 "C:\CRE\vues_v1.txt" `
    -Path2 "C:\CRE\vues_v2.txt" `
    -OutputPath "C:\CRE\differences.csv"
```

### 4.2 Deux colonnes de feuilles différentes, dans le même classeur

C'est votre cas : vérifier que tous les CRE de la feuille `CRE` sont bien présents
dans `MAPPING_CRE`.

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 "C:\CRE\CRE.xlsx" -Sheet1 "CRE"         -Column1 "CRE" `
    -Path2 "C:\CRE\CRE.xlsx" -Sheet2 "MAPPING_CRE" -Column2 "CRE" `
    -Mode Columns `
    -OutputSheet "COMPARAISON_CRE"
```

Le résultat s'écrit dans une nouvelle feuille du classeur, avec sauvegarde préventive
automatique dans `C:\CRE\_backup\`.

### 4.3 Deux colonnes de fichiers différents

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 "C:\CRE\CRE.xlsx"  -Sheet1 "MAPPING_CRE" -Column1 "CRE" `
    -Path2 "C:\CRE\base.xlsx" -Sheet2 "RESULTAT 1"  -Column2 "CRE" `
    -Mode Columns `
    -OutputPath "C:\CRE\ecarts_cre.xlsx"
```

### 4.4 Contrôle de migration, champ par champ

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 "C:\Data\avant.csv" `
    -Path2 "C:\Data\apres.csv" `
    -Mode KeyedRows `
    -KeyColumns "ID" `
    -OutputPath "C:\Data\ecarts_migration.csv"
```

Clé composite et colonnes ciblées :

```powershell
    -KeyColumns "CompteID","DateOperation" `
    -CompareColumns "Montant","Statut"
```

### 4.5 Comparaison tolérante (casse, accents, espaces)

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 a.csv -Path2 b.csv `
    -IgnoreAccents -NormalizeWhitespace -IgnoreEmptyLines `
    -OutputPath diff.csv
```

### 4.6 Désigner une colonne sans en connaître le nom

Trois notations acceptées, indifféremment :

```powershell
-Column1 "CRE"    # par nom d'en-tête (recommandé, le plus explicite)
-Column1 "A"      # par lettre Excel (A, B, ... Z, AA, AC...)
-Column1 "1"      # par index numérique
```

### 4.7 Journalisation complète

```powershell
.\Compare-DataFiles.ps1 `
    -Path1 a.csv -Path2 b.csv `
    -OutputPath diff.csv `
    -LogPath "C:\CRE\logs\comparaison_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
```

---

## 5. Tous les paramètres

### Sources

| Paramètre | Défaut | Rôle |
|---|---|---|
| `-Path1` | *(obligatoire)* | Première source |
| `-Path2` | *(obligatoire)* | Deuxième source |
| `-Sheet1` / `-Sheet2` | 1re feuille | Feuilles Excel |
| `-Column1` / `-Column2` | — | Colonne (nom, lettre ou index) |

### Mode

| Paramètre | Défaut | Rôle |
|---|---|---|
| `-Mode` | `Auto` | TextPositional, TextSet, Columns, KeyedRows |
| `-KeyColumns` | — | Colonne(s) clé en mode KeyedRows |
| `-CompareColumns` | toutes | Colonnes à comparer en mode KeyedRows |

### Options de comparaison

| Paramètre | Défaut | Effet |
|---|---|---|
| `-CaseSensitive` | off | La casse devient significative |
| `-NoTrim` | off | Conserve les espaces de bord |
| `-IgnoreEmptyLines` | off | Ignore les lignes vides |
| `-NormalizeWhitespace` | off | Réduit les espaces multiples à un seul |
| `-IgnoreAccents` | off | « Différentiel » = « Differentiel » |

### Sortie

| Paramètre | Défaut | Effet |
|---|---|---|
| `-OutputPath` | — | Fichier `.csv`, `.txt` ou `.xlsx` |
| `-OutputSheet` | — | Nouvelle feuille dans `-Path1` (Excel) |
| `-IncludeMatches` | off | Inclut aussi les lignes identiques |
| `-MaxDifferences` | 0 | Arrête après N écarts (0 = illimité) |
| `-NoBackup` | off | Désactive la sauvegarde préventive |
| `-Delimiter` | *(auto)* | Séparateur CSV |
| `-LogPath` | — | Fichier de log |

Sans `-OutputPath` ni `-OutputSheet`, un aperçu des 20 premières différences s'affiche
en console — pratique pour un test rapide.

---

## 6. Comprendre les statuts du rapport

Le rapport a toujours les mêmes 8 colonnes, quel que soit le mode :
`STATUT`, `LIGNE_1`, `VALEUR_1`, `LIGNE_2`, `VALEUR_2`, `CLE`, `COLONNE`, `DETAIL`.

| STATUT | Signification |
|---|---|
| `DIFFERENTE` | Même position, contenu différent (positionnel) |
| `ABSENTE_DE_2` | Le fichier 1 a plus de lignes |
| `AJOUTEE_DANS_2` | Le fichier 2 a plus de lignes |
| `SEULEMENT_DANS_1` | Valeur présente dans 1, absente de 2 |
| `SEULEMENT_DANS_2` | Valeur présente dans 2, absente de 1 |
| `NOMBRE_OCCURRENCES_DIFFERENT` | Présente des deux côtés, mais pas autant de fois |
| `PRESENT_DANS_LES_DEUX` | Correspondance (avec `-IncludeMatches`) |
| `AJOUTEE` | Clé présente seulement dans 2 (KeyedRows) |
| `SUPPRIMEE` | Clé présente seulement dans 1 (KeyedRows) |
| `MODIFIEE` | Clé commune, champ différent — la colonne est précisée |
| `DOUBLON_DANS_1` / `DOUBLON_DANS_2` | Clé en double |
| `IDENTIQUE` | Aucun écart (avec `-IncludeMatches`) |

Le bilan de fin d'exécution donne le décompte par statut : vous voyez immédiatement
la nature des écarts sans ouvrir le fichier.

---

## 7. Performance

Les choix techniques garantissent un traitement rapide même sur de gros volumes :

| Technique | Bénéfice |
|---|---|
| `StreamReader` | Mémoire constante quelle que soit la taille du fichier |
| Dictionnaires (accès O(1)) | 100 000 × 100 000 lignes : 200 000 opérations au lieu de 10 milliards |
| Lecture Excel en un seul appel COM | ~100× plus rapide que cellule par cellule |
| `List[T]` au lieu de `+=` | Évite la recopie du tableau à chaque ajout |
| `StringBuilder` | Construction du rapport texte sans concaténation |
| `-MaxDifferences` | Arrêt anticipé quand on veut juste un échantillon |

Ordres de grandeur observables : deux fichiers de 100 000 lignes se comparent en
quelques secondes ; l'écriture Excel, volontairement cellule par cellule pour la
fiabilité, est le poste le plus lent au-delà de ~20 000 lignes de résultat — dans ce
cas, préférez `-OutputPath` en `.csv`.

---

## 8. Dépannage

| Symptôme | Cause / solution |
|---|---|
| `n'est pas signé numériquement` | `Unblock-File -Path "C:\CRE\Compare-DataFiles.ps1"` |
| `Feuille 'X' introuvable` | Le message liste les feuilles disponibles — copiez le nom exact |
| `colonne 'X' introuvable` | Le message liste les en-têtes trouvés |
| `Pour un fichier Excel, précisez -Column1/-Column2` | Le mode Auto ne devine pas : ajoutez `-Mode Columns` ou `-KeyColumns` |
| `-OutputSheet nécessite que -Path1 soit un fichier Excel` | Utilisez `-OutputPath` à la place |
| Accents corrompus dans le CSV de sortie | Le CSV est écrit avec BOM pour Excel — normal |
| Trop de différences signalées | Ajoutez `-IgnoreEmptyLines`, `-NormalizeWhitespace` ou `-IgnoreAccents` |
| Le classeur ne se sauvegarde pas | Fermez-le dans Excel avant de lancer le script |
| `EXCEL.EXE` reste en mémoire | Ne devrait pas arriver (libération en `finally`) ; sinon, gestionnaire des tâches |

### En cas d'erreur

Le script affiche automatiquement : **étape**, **fonction**, **fichier**, **ligne et
colonne**, **code fautif**, type .NET, exceptions internes et pile d'appel, plus le
contexte (chemins, mode, feuilles, colonnes).

Une seule capture d'écran de ce bloc suffit pour localiser le problème.
