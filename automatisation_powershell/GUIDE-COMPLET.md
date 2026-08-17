# Boîte à outils ETL — Guide complet

Package d'automatisation pour les tâches quotidiennes d'analyse et de croisement
de données : comparaisons, doublons, filtrages, extractions, contrôles de cohérence.

**Aucun droit administrateur. Aucun module à installer. Fichiers de données où vous voulez.**

---

## Table des matières

1. [Démarrage en 3 minutes](#1-démarrage-en-3-minutes)
2. [Contenu du package](#2-contenu-du-package)
3. [Comprendre l'architecture](#3-comprendre-larchitecture)
4. [L'interface interactive](#4-linterface-interactive)
5. [Les 40 cas d'utilisation](#5-les-40-cas-dutilisation)
6. [Le laboratoire de test](#6-le-laboratoire-de-test)
7. [Lire et comprendre les logs](#7-lire-et-comprendre-les-logs)
8. [Performance](#8-performance)
9. [Dépannage](#9-dépannage)

---

## 1. Démarrage en 3 minutes

### Étape 1 — Installer

Copiez tout le dossier où vous voulez, par exemple `C:\CRE\`.
Les fichiers de données peuvent être **ailleurs**, sur un autre disque, un partage
réseau — aucune importance, tous les chemins sont paramétrables.

### Étape 2 — Lancer

**Double-cliquez sur `Lancer-Toolkit.bat`.**

C'est tout. Le fichier `.bat` débloque automatiquement les scripts (nécessaire après
un transfert par GitHub) et ouvre le menu.

Depuis PowerShell, l'équivalent est :

```powershell
cd C:\CRE
.\Start-Toolkit.ps1
```

### Étape 3 — Créer un jeu de test

Dans le menu, choisissez **`10. Créer un jeu de données de test`**.

Cela génère un dossier `LAB` contenant des fichiers CSV, Excel, TXT, XML, JSON et SQL
avec des anomalies volontaires. Vous pouvez alors essayer **toutes** les fonctions
sans aucun risque pour vos vraies données.

### Étape 4 — Essayer

Choisissez `1. Comparer deux fichiers` et indiquez :
- `LAB\01_TEXTE\vues.txt`
- `LAB\01_TEXTE\vues_v2.txt`

Le programme vous montre les différences **et** la commande PowerShell équivalente,
que vous pouvez réutiliser directement.

---

## 2. Contenu du package

### Programmes (à exécuter)

| Fichier | Rôle |
|---|---|
| `Lancer-Toolkit.bat` | **Point d'entrée** — double-clic |
| `Start-Toolkit.ps1` | Interface interactive à menus |
| `Compare-DataFiles.ps1` | Comparaison universelle |
| `Resolve-CreViewAliases.ps1` | Résolution des alias de vues (métier CRE) |
| `Extract-CreTableColumns.ps1` | Extraction tables/colonnes des requêtes (métier CRE) |
| `New-TestLab.ps1` | Générateur de jeu de test |

### Bibliothèques (à importer dans vos propres scripts)

| Fichier | Rôle |
|---|---|
| `PSToolkit.psm1` | 42 fonctions ETL |
| `PSToolkit-Trace.psm1` | 11 fonctions de traçage |

### Documentation

| Fichier | Contenu |
|---|---|
| `GUIDE-COMPLET.md` | Ce document |
| `FORMATION-POWERSHELL.md` | Cours PowerShell en 20 chapitres |
| `COMPARE-GUIDE.md` | Détail de `Compare-DataFiles` |

---

## 3. Comprendre l'architecture

### Deux natures de fichiers

C'est le point qui prête le plus à confusion :

**Les scripts `.ps1` sont des programmes autonomes.** On les lance, ils travaillent,
ils s'arrêtent. Aucune préparation.

```powershell
.\Compare-DataFiles.ps1 -Path1 a.csv -Path2 b.csv -OutputPath diff.csv
```

**Les modules `.psm1` sont des bibliothèques.** On ne les lance pas : on les charge,
puis on appelle leurs fonctions dans ses propres scripts.

```powershell
Import-Module "C:\CRE\PSToolkit.psm1" -Force
Import-ExcelSheet -Path "C:\Data\fichier.xlsx" -SheetName 'Feuil1'
```

Oublier l'`Import-Module` produit l'erreur *« le terme X n'est pas reconnu »*.

**Vous n'avez pas besoin des modules pour utiliser l'interface** : elle n'appelle que
des scripts autonomes.

### Organisation objet

Les scripts sont structurés en classes, comme un vrai programme :

| Classe | Fichier | Responsabilité |
|---|---|---|
| `ContexteToolkit` | Start-Toolkit | État partagé : dossiers, historique |
| `Affichage` | Start-Toolkit | Tout ce qui s'affiche à l'écran |
| `Saisie` | Start-Toolkit | Questions à l'utilisateur, avec validation |
| `Executeur` | Start-Toolkit | Lancement des scripts et gestion d'erreur |
| `Journal` | New-TestLab | Journalisation à niveaux |
| `EcrivainTexte` | New-TestLab | Écriture avec contrôle du BOM |
| `ConstructeurExcel` | New-TestLab | Création de classeurs multi-feuilles |

Chaque classe regroupe son état et ses comportements, au lieu de disperser des
variables globales. Pour modifier l'apparence du menu, vous ne touchez qu'à
`Affichage` ; pour ajouter une question, qu'à `Saisie`.

### Séparation des dossiers

Rien n'oblige à mettre les données à côté des scripts :

```powershell
.\Start-Toolkit.ps1 -DataFolder "D:\Exports\Aout2026" -OutputFolder "D:\Resultats"
```

Ces deux dossiers sont aussi modifiables en cours de session (menu 11).

---

## 4. L'interface interactive

### Principes

- **Rien à mémoriser** : le programme pose les questions, vous répondez.
- **Les feuilles et colonnes Excel sont proposées en liste** — pas de faute de frappe possible.
- **`0` annule** à n'importe quelle question.
- **La commande équivalente est affichée** après chaque action : vous apprenez en
  faisant, et pouvez copier la commande pour l'automatiser plus tard.
- **Glisser-déposer** : faites glisser un fichier dans la fenêtre pour coller son chemin.

### Le menu

```
COMPARER
  1. Comparer deux fichiers texte ou CSV
  2. Comparer deux colonnes Excel
  3. Contrôler une migration (avant / après, champ par champ)

EXPLORER
  4. Analyser un fichier inconnu (structure, qualité)
  5. Rechercher un texte dans plusieurs fichiers

TRANSFORMER
  6. Extraire les valeurs uniques / détecter les doublons
  7. Filtrer un tableau à partir d'une liste
  8. Fusionner plusieurs fichiers CSV

MÉTIER
  9. Traitements CRE (mapping, alias de vues)

OUTILS
 10. Créer un jeu de données de test
 11. Configuration et informations système
```

### Les sorties

Tous les résultats vont dans le dossier `SORTIES\`, horodatés :

```
SORTIES\comparaison_20260815_143052.csv
SORTIES\profil_donnees_20260815_143120.csv
SORTIES\_logs\comparaison_20260815_143052.log
```

Rien n'est jamais écrasé. Avant toute modification d'un classeur Excel, une
sauvegarde est créée dans `_backup\`.

---

## 5. Les 40 cas d'utilisation

### A. Contrôle de cohérence après une requête SQL

Vous exécutez une requête, collez le résultat dans Excel, et voulez le croiser.

| Besoin | Menu | Commande |
|---|---|---|
| Ma liste SQL correspond-elle au référentiel ? | 2 | `Compare-DataFiles -Mode Columns` |
| Y a-t-il des doublons dans ma clé ? | 6 | menu 6 sur la colonne clé |
| Quelles valeurs sont orphelines ? | 2 | statut `SEULEMENT_DANS_1` |
| Mon export est-il complet ? | 4 | profilage : taux de remplissage |

```powershell
# Colonne d'un export SQL contre le référentiel
.\Compare-DataFiles.ps1 `
    -Path1 "D:\SQL\resultat_requete.xlsx" -Sheet1 "Feuil1" -Column1 "CODE_CLIENT" `
    -Path2 "D:\Ref\referentiel.xlsx"      -Sheet2 "DONNEES" -Column2 "CODE_CLIENT" `
    -Mode Columns -OutputPath "D:\Sorties\orphelins.csv"
```

### B. Croisement de plusieurs sources

| Besoin | Menu |
|---|---|
| Filtrer 100 000 lignes selon une liste de 50 codes | 7 |
| Consolider 30 exports quotidiens | 8 |
| Comparer une feuille Excel avec un fichier TXT | 2 |
| Extraire les lignes présentes dans A **et** B | 2 avec `-IncludeMatches` |

```powershell
# Filtrer un gros tableau à partir d'une liste tenue dans une autre feuille
# (via le menu 7 : plus simple, il vous guide)
```

### C. Détection d'anomalies

| Besoin | Menu | Statut à filtrer |
|---|---|---|
| Doublons sur une clé métier | 6 | `OCCURRENCES > 1` |
| Lignes ajoutées / supprimées | 3 | `AJOUTEE`, `SUPPRIMEE` |
| Quel champ précis a changé ? | 3 | `MODIFIEE` + colonne `COLONNE` |
| Valeurs manquantes | 4 | profil : colonne `VIDES` |
| Formats invalides | 4 | profil : colonne `TYPE` |

```powershell
# Contrôle de migration complet
.\Compare-DataFiles.ps1 `
    -Path1 "D:\Avant\clients.csv" -Path2 "D:\Apres\clients.csv" `
    -Mode KeyedRows -KeyColumns "CODE_CLIENT" `
    -OutputPath "D:\Sorties\ecarts.csv"
```

### D. Exploration et recherche

| Besoin | Menu |
|---|---|
| Où cette table est-elle utilisée dans mes scripts ? | 5 |
| Combien de lignes dans ce fichier de 5 Go ? | 4 |
| Quel est l'encodage de ce fichier ? | 4 |
| Quel séparateur utilise ce CSV ? | 4 |
| Quelles erreurs dans mes logs ? | 5 avec motif `ORA-` |

### E. Nettoyage et préparation

| Besoin | Fonction |
|---|---|
| Convertir ANSI → UTF-8 | `Convert-FileEncoding` (module) |
| Découper un fichier trop gros pour Excel | `Split-LargeFile` (module) |
| Supprimer les doublons | menu 6 |
| Typer les colonnes (texte → nombre/date) | `ConvertTo-TypedObject` (module) |

### F. Traitements métier CRE

| Besoin | Menu |
|---|---|
| Extraire tables/colonnes des requêtes CRE | 9 → 1 |
| Résoudre les alias de vues | 9 → 2 |
| Vérifier que tous les CRE sont mappés | 2 (colonne CRE des deux feuilles) |

### G. Avec les modules, dans vos propres scripts

```powershell
Import-Module "C:\CRE\PSToolkit.psm1" -Force
Import-Module "C:\CRE\PSToolkit-Trace.psm1" -Force

Start-Trace -LogPath "D:\Logs\mon_traitement.log"

$data = Invoke-Step -Name 'Lecture' -Action {
    Import-ExcelSheet -Path "D:\Data\source.xlsx" -SheetName 'Données'
}

$propre = Invoke-Step -Name 'Nettoyage' -Action {
    $data | ConvertTo-TypedObject -Schema @{ Montant = 'decimal'; Date = 'datetime' }
}

Invoke-Step -Name 'Contrôle qualité' -Action {
    $propre | Test-DataQuality -Rules @{
        CODE = @{ Required = $true; Unique = $true }
        Montant = @{ MinValue = 0 }
    }
}

Stop-Trace
```

---

## 6. Le laboratoire de test

### Génération

Menu `10`, ou directement :

```powershell
.\New-TestLab.ps1 -Path "D:\LAB" -Force
```

### Contenu

```
LAB\
├── 01_TEXTE\      vues.txt, vues_v2.txt, listes, log 300 lignes, largeur fixe
├── 02_CSV\        clients (204 l.), ventes (500 l.), produits TSV, ANSI, quotidien\
├── 03_XML_JSON\   tables.json, tables_INVALIDE.json, referentiel.xml
├── 04_EXCEL\      CRE.xlsx (4 feuilles), base.xlsx (2), donnees_croisement.xlsx (3)
├── 05_SQL\        creation_jeu_test.sql
├── 99_SORTIES\    dossier vide pour vos résultats
└── LISEZMOI.txt   inventaire détaillé
```

### Anomalies volontaires

Le laboratoire contient **délibérément** des données problématiques, pour vérifier
que les outils les détectent au lieu de planter :

| Anomalie | Où |
|---|---|
| Doublons | CLI0007 et CLI0042 en double |
| Casse incohérente | `cre_parties` en minuscules |
| Ligne vide | fin de `liste_A.txt` |
| Valeur manquante | CLI9998 sans raison sociale |
| Format invalide | `XXX123`, montant `abc`, date `pas-une-date` |
| Montant négatif | CLI9998 à −500,00 |
| Jointure trouée | PRD017 absent du référentiel |
| CRE orphelin | `CRE_CRE_ABSENT_DE_BASE` |
| Colonne inexistante | `colonne_qui_nexiste_pas` |
| Vue non définie | `V_TFT_K_VUE_NON_DEFINIE` |
| JSON erroné | `tables_INVALIDE.json` |
| Encodage ANSI | `export_ancien_ansi.csv` |

### Scénarios de test recommandés

| # | Test | Menu | Fichiers | Résultat attendu |
|---|---|---|---|---|
| 1 | Comparaison texte | 1 | `vues.txt` / `vues_v2.txt` | 1 ligne différente + 4 ajoutées |
| 2 | Listes | 1 (mode 2) | `liste_A.txt` / `liste_B.txt` | valeurs propres à chacune |
| 3 | Colonnes Excel | 2 | `CRE.xlsx` MAPPING_CRE / CRE_DISTINCTS | CRE non mappés |
| 4 | Migration | 3 | `clients.csv` / `clients_apres_migration.csv` | 8 supprimées, ~21 modifiées, 15 ajoutées |
| 5 | Profilage | 4 | `clients.csv` | 7 colonnes, anomalies visibles |
| 6 | Recherche | 5 | `01_TEXTE`, motif `ORA-` | ~17 occurrences |
| 7 | Doublons | 6 | `clients.csv` colonne CODE_CLIENT | CLI0007, CLI0042 |
| 8 | Filtrage | 7 | `donnees_croisement.xlsx` DONNEES + LISTE_A_EXTRAIRE | 7 lignes sur 8 (CLI9999 absent) |
| 9 | Fusion | 8 | `02_CSV\quotidien` | 250 lignes |
| 10 | Mapping CRE | 9→1 | `CRE.xlsx` + `tables.json` | mapping produit |
| 11 | Alias de vues | 9→2 | `CRE.xlsx` + `base.xlsx` + `vues.txt` | alias résolus + 1 vue non définie signalée |
| 12 | JSON invalide | 9→1 | avec `tables_INVALIDE.json` | message d'erreur clair, pas de plantage |

**Le test 12 est important** : il vérifie que le diagnostic fonctionne. Un message
d'erreur clair est le comportement *attendu*, pas un échec.

---

## 7. Lire et comprendre les logs

### Format à l'écran

```
> ETAPE 1 : Vérification des fichiers
  [+] Fichier 1 : 12 450 octets (CSV)
  [+] Fichier 2 : 11 980 octets (CSV)
< OK    Vérification des fichiers (0,1s)

> ETAPE 2 : Comparaison
  [i] 204 lignes lues
  [!] 3 doublons détectés
< OK    Comparaison (0,4s)
```

| Symbole | Sens |
|---|---|
| `> ETAPE n` | Début d'une étape |
| `< OK` | Fin réussie, avec durée |
| `[+]` | Succès |
| `[i]` | Information |
| `[!]` | Avertissement — à regarder, mais pas bloquant |
| `[X]` | Erreur |
| L'indentation | Niveau d'imbrication : montre *où* ça s'est passé |

### En cas d'erreur

```
##############################################################################
#  ERREUR
##############################################################################
#  ETAPE       : Lecture de la feuille MAPPING_CRE
#  FONCTION    : Read-SheetData
#  FICHIER     : Resolve-CreViewAliases.ps1
#  LIGNE       : 412 (colonne 9)
#  CODE FAUTIF : $data = $ws.UsedRange.Value2
#  MESSAGE     : Feuille 'MAPPING_CRE' introuvable
#  TYPE .NET   : System.Management.Automation.RuntimeException
#-----------------------------------------------------------------------------
#  CONTEXTE :
#    ExcelPath = D:\LAB\04_EXCEL\CRE.xlsx
##############################################################################
```

**Comment lire ce bloc :**

1. `ETAPE` — à quel moment du traitement (le plus utile)
2. `FONCTION` + `LIGNE` — où corriger dans le code
3. `CODE FAUTIF` — l'instruction exacte
4. `MESSAGE` — la cause
5. `CONTEXTE` — avec quelles données

Une seule capture d'écran de ce bloc suffit à localiser n'importe quel problème.

### Fichiers de log

Chaque exécution écrit dans `SORTIES\_logs\`, horodaté. Les logs ne sont jamais
écrasés : vous pouvez comparer deux exécutions successives (avec le menu 1 !).

---

## 8. Performance

| Technique | Où | Gain |
|---|---|---|
| `StreamReader` (lecture en flux) | tous les fichiers texte | mémoire constante, même sur 5 Go |
| Dictionnaires / `HashSet` (O(1)) | comparaisons, filtrages, doublons | ×100 à ×10 000 |
| `List[T]` au lieu de `+=` | partout | ×100 à ×1000 |
| Lecture Excel en 1 appel COM | `UsedRange.Value2` | ×100 |
| Regex compilée hors boucle | recherches | ×5 à ×10 |
| `StringBuilder` | construction de rapports | ×50 |
| Écriture CSV en flux | fusion | mémoire constante |

**Ordres de grandeur** : comparer deux fichiers de 100 000 lignes prend quelques
secondes. Filtrer 100 000 lignes avec une liste de 1 000 valeurs est quasi instantané
(1 000 000 000 de comparaisons évitées grâce au `HashSet`).

**Le poste le plus lent est l'écriture Excel**, volontairement cellule par cellule
pour la fiabilité. Au-delà de ~20 000 lignes de résultat, préférez une sortie CSV.

---

## 9. Dépannage

| Symptôme | Solution |
|---|---|
| « n'est pas signé numériquement » | Double-cliquez sur `Lancer-Toolkit.bat` : il débloque tout |
| « l'exécution de scripts est désactivée » | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| « le terme X n'est pas reconnu » | Fonction d'un module : `Import-Module "C:\CRE\PSToolkit.psm1" -Force` |
| « Feuille 'X' introuvable » | Le message liste les feuilles disponibles ; utilisez le menu, qui les propose |
| « colonne 'X' introuvable » | Le message liste les en-têtes trouvés |
| Le classeur ne se sauvegarde pas | Fermez-le dans Excel avant de lancer |
| Accents corrompus dans le CSV | Normal à l'ouverture Notepad ; correct dans Excel (BOM) |
| `EXCEL.EXE` reste en mémoire | Ne devrait pas arriver ; sinon gestionnaire des tâches |
| Trop de différences signalées | Répondez « oui » à la tolérance, ou ajoutez `-IgnoreAccents` |
| Traitement lent sur gros volume | Sortie CSV plutôt qu'Excel |
| `Primitive JSON non valide` | BOM ou syntaxe : validez le JSON avant |

### Le réflexe après chaque récupération depuis GitHub

```powershell
Get-ChildItem -Path "C:\CRE\*.ps1","C:\CRE\*.psm1" | Unblock-File
```

Ou plus simple : double-cliquez sur `Lancer-Toolkit.bat`, qui le fait automatiquement.

### Signaler un problème efficacement

1. Relancez avec un log : le menu le fait automatiquement
2. Photographiez le bloc `#### ERREUR ####`
3. Précisez : quel menu, quels fichiers, et le résultat attendu

Les informations `ETAPE`, `FONCTION`, `LIGNE` et `CODE FAUTIF` suffisent presque
toujours à identifier la cause sans autre aller-retour.
