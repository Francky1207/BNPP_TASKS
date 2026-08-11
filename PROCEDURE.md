# Procédure — Extraction CRE / TABLE / COLONNES

Automatisation de la cartographie des CRE (type `Différentiel`, statut `Valide`) vers les tables et
colonnes ciblées, à partir de la colonne `REQUEST` (SQL) de la feuille `CRE`.

---

## 1. Prérequis

- Windows avec **Microsoft Excel installé** (le script pilote Excel via COM).
- **PowerShell 5.1** (natif Windows) ou supérieur.
- Le classeur `.xlsx` **fermé** dans Excel au moment de l'exécution (sinon ouverture en lecture seule
  et échec de la sauvegarde).

---

## 2. Arborescence des fichiers

```
C:\CRE\
├── Extract-CreTableColumns.ps1   <- le script
├── tables.json                   <- config : tables + colonnes à rechercher
└── CRE.xlsx                      <- le fichier Excel source
```

> Le script cherche `tables.json` **dans son propre dossier** par défaut.
> Le chemin peut être surchargé avec `-ConfigPath`.

---

## 3. Où va le résultat

L'output est écrit **dans `CRE.xlsx` lui-même**, dans une nouvelle feuille nommée `MAPPING_CRE` :

| CRE | TABLE | COLONNES |
|-----|-------|----------|
| CRE_ELT_NETWORKS | kbr_elt_networks | CONTACT_EMAIL, CONTACT_PHONE, BANK_ACCOUNT |

- Aucun fichier n'est écrasé : la feuille est **supprimée puis recréée** à chaque exécution.
- Les autres feuilles (`Objets`, `Codifications`, `CRE`, `Tables`, …) ne sont pas modifiées.
- Un export CSV optionnel est disponible via `-CsvPath`.

---

## 4. Configuration `tables.json`

Seul fichier à maintenir au quotidien. Une entrée par table, avec la collection de champs à
rechercher dans la requête :

```json
{
  "kpa_parties": [
    "PARTY_ID",
    "LEGAL_FORM",
    "ANNUAL_REVENUE",
    "PRIMARY_ACTIVITY_CODE"
  ],
  "kbr_elt_networks": [
    "CONTACT_EMAIL",
    "CONTACT_PHONE",
    "BANK_ACCOUNT",
    "ORIAS_NUMBER"
  ]
}
```

Encodage : **UTF-8**. Casse indifférente pour les noms de tables et de colonnes.

---

## 5. Exécution

### 5.1 Commande simple

```powershell
cd C:\CRE
.\Extract-CreTableColumns.ps1 -ExcelPath "C:\CRE\CRE.xlsx"
```

### 5.2 Si l'exécution de scripts est bloquée sur le poste

```powershell
powershell -ExecutionPolicy Bypass -File "C:\CRE\Extract-CreTableColumns.ps1" -ExcelPath "C:\CRE\CRE.xlsx"
```

Depuis une invite **cmd** :

```cmd
powershell -ExecutionPolicy Bypass -File "C:\CRE\Extract-CreTableColumns.ps1" -ExcelPath "C:\CRE\CRE.xlsx"
```

### 5.3 Version complète recommandée (1er passage, contrôle avant validation)

```powershell
.\Extract-CreTableColumns.ps1 `
    -ExcelPath   "C:\CRE\CRE.xlsx" `
    -ConfigPath  "C:\CRE\tables.json" `
    -SourceSheet "CRE" `
    -TargetSheet "MAPPING_CRE" `
    -CsvPath     "C:\CRE\mapping.csv" `
    -KeepEmptyCre `
    -BlankRepeatedCre `
    -StrictTables
```

Deux sorties sont alors produites :
- la feuille `MAPPING_CRE` dans `C:\CRE\CRE.xlsx`
- le fichier `C:\CRE\mapping.csv` (séparateur `;`, UTF-8)

Ajouter `-NoExcelOutput` pour ne générer **que** le CSV sans toucher au classeur.

---

## 6. Paramètres

| Paramètre | Défaut | Rôle |
|-----------|--------|------|
| `-ExcelPath` | *(obligatoire)* | Chemin du classeur à traiter |
| `-ConfigPath` | `tables.json` à côté du script | Fichier JSON tables/colonnes |
| `-SourceSheet` | `CRE` | Feuille source à analyser |
| `-TargetSheet` | `MAPPING_CRE` | Feuille de résultat créée |
| `-TypeCre` | `Differentiel` | Valeur filtrée sur `TYPE_CRE` |
| `-Status` | `Valide` | Valeur filtrée sur `CRE_STATUS` |
| `-CsvPath` | *(aucun)* | Export CSV supplémentaire |
| `-KeepEmptyCre` | off | Conserve une ligne vide pour les CRE sans table ciblée |
| `-BlankRepeatedCre` | off | Ne répète pas le nom du CRE sur les lignes suivantes |
| `-OneRowPerColumn` | off | Une ligne par colonne au lieu d'une liste concaténée |
| `-StrictTables` | off | La table doit apparaître dans un `FROM`/`JOIN` (moins de faux positifs) |
| `-LooseColumns` | off | Accepte les colonnes non préfixées même quand un alias existe (plus permissif) |
| `-RequireColumn` | off | Ignore les tables détectées sans aucune colonne ciblée |
| `-NoExcelOutput` | off | N'écrit pas dans le classeur (à combiner avec `-CsvPath`) |

---

## 7. Logique de détection

**Filtrage des lignes** : `TYPE_CRE = Différentiel` **et** `CRE_STATUS = Valide`.
La comparaison ignore la casse **et les accents**, le script reste donc ASCII et fonctionne quel que
soit l'encodage du fichier.

**Détection des tables** : recherche de chaque table de `tables.json` dans le SQL. Avec
`-StrictTables`, seules les tables déclarées dans un `FROM`, `JOIN`, `UPDATE` ou `INTO` sont retenues.

**Détection des colonnes**, par ordre de priorité :

1. Référence qualifiée par l'alias résolu depuis le `FROM` — `FROM KBR_ELT_NETWORKS KEN` → recherche `KEN.CONTACT_EMAIL`
2. Référence qualifiée par le nom de table — `KPA_PARTIES.PARTY_ID`
3. `SELECT KEN.*` → toutes les colonnes configurées de la table sont considérées présentes
4. Repli sur le nom nu (`PARTY_ID`) si aucun alias n'a pu être identifié, ou avec `-LooseColumns`

**Cas particuliers** :
- Un CRE peut produire **plusieurs lignes** (une par table détectée dans sa requête).
- Un CRE sans table ciblée est ignoré, sauf avec `-KeepEmptyCre` (ligne à `TABLE`/`COLONNES` vides).
- Une table détectée sans colonne ciblée sort avec `COLONNES` vide, sauf avec `-RequireColumn`.

---

## 8. Performance

- Lecture de la feuille en **un seul appel COM** (`UsedRange.Value2` → tableau 2D en mémoire).
- Chaque requête SQL est indexée **une seule fois** par 3 regex compilées, puis interrogée par
  `HashSet` / `Dictionary` en O(1) : aucune regex n'est construite dans la boucle.
- Écriture du résultat en **un seul appel COM** (tableau 2D assigné à la plage).
- `ScreenUpdating` et `EnableEvents` désactivés, objets COM libérés dans un bloc `finally`.

---

## 9. Dépannage

| Symptôme | Cause / solution |
|----------|------------------|
| `Fichier de configuration introuvable` | `tables.json` absent du dossier du script → utiliser `-ConfigPath` |
| `Feuille 'CRE' introuvable` | Nom de feuille différent → utiliser `-SourceSheet` |
| `Entetes 'CRE' et/ou 'REQUEST' introuvables` | Les en-têtes doivent être sur la **première ligne** de la plage utilisée |
| Sauvegarde impossible | Le classeur est ouvert dans Excel → le fermer avant d'exécuter |
| `L'exécution de scripts est désactivée` | Utiliser `powershell -ExecutionPolicy Bypass -File ...` |
| Résultat vide | Vérifier les valeurs réelles de `TYPE_CRE` / `CRE_STATUS` et les surcharger via `-TypeCre` / `-Status` |
| Trop de tables détectées | Ajouter `-StrictTables` |
| Colonnes manquantes | Ajouter `-LooseColumns` |
