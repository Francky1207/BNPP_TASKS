# Boîte à outils PowerShell — automatisation ETL / Datawarehouse

Ensemble complet : une formation, une bibliothèque de 42 fonctions réutilisables,
et un recueil de recettes prêtes à l'emploi.

**Aucun droit administrateur requis. Aucun module externe à installer.**

---

## Les 4 fichiers

| Fichier | Rôle |
|---|---|
| `FORMATION-POWERSHELL.md` | Cours complet en 20 chapitres (dont la POO) |
| `PSToolkit.psm1` | Bibliothèque de 42 fonctions documentées |
| `PSToolkit-Recettes.ps1` | 15 recettes prêtes à copier-coller |
| `README.md` | Ce fichier |

---

## Installation

Placez les fichiers dans un dossier, par exemple `C:\CRE\` :

```
C:\CRE\
├── PSToolkit.psm1
├── PSToolkit-Recettes.ps1
├── FORMATION-POWERSHELL.md
└── README.md
```

Puis, dans PowerShell :

```powershell
# Une seule fois : débloquer les fichiers venant de GitHub
Unblock-File -Path "C:\CRE\*.ps1"
Unblock-File -Path "C:\CRE\*.psm1"

# À chaque session
Import-Module "C:\CRE\PSToolkit.psm1" -Force
```

Vérification :

```powershell
Get-Command -Module PSToolkit          # doit lister 42 fonctions
Get-Help Import-CsvFast -Full          # aide détaillée
Get-Help Test-DataQuality -Examples    # juste les exemples
```

### Chargement automatique à chaque démarrage (optionnel)

```powershell
# Crée le profil s'il n'existe pas, puis y ajoute l'import
if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force }
Add-Content -Path $PROFILE -Value 'Import-Module "C:\CRE\PSToolkit.psm1" -Force'
```

Le profil se trouve dans votre dossier utilisateur — aucun droit admin nécessaire.

---

## Les 42 fonctions par domaine

### Journalisation
`Start-LogSession` · `Stop-LogSession` · `Write-Log`

### Encodage (le piège n°1 en ETL français)
`Get-FileEncoding` · `Read-TextFile` · `Write-TextFile` · `Convert-FileEncoding`

### Fichiers texte volumineux
`Measure-FileLine` · `Search-InFile` · `Split-LargeFile` · `Get-FileHead` · `Get-FileTail`

### CSV
`Get-CsvDelimiter` · `Import-CsvFast` · `ConvertTo-TypedObject` · `Export-CsvFast` · `Merge-CsvFile`

### Qualité de données
`Get-DataProfile` · `Find-DuplicateRow` · `Compare-DataSet` · `Test-DataQuality`

### Excel (COM)
`New-ExcelApp` · `Close-ExcelApp` · `Get-ExcelSheetName` · `Import-ExcelSheet` ·
`Export-ExcelSheet` · `Convert-ExcelToCsv`

### SQL Server (sans module, sans admin)
`Get-SqlConnectionString` · `Test-SqlConnection` · `Invoke-SqlQuery` ·
`Invoke-SqlNonQuery` · `Import-ToSqlTable` · `Get-SqlTableSchema`

### Fichiers et classement
`Get-FileInventory` · `Find-DuplicateFile` · `Move-FileByRule` · `Backup-File` · `Remove-OldFile`

### Utilitaires
`New-Timer` · `Get-Timing` · `Test-IsNumeric` · `ConvertTo-SafeName`

---

## Démarrage rapide — 3 exemples

**Découvrir un fichier inconnu**

```powershell
Import-CsvFast -Path .\mystere.csv | Get-DataProfile | Format-Table -AutoSize
```

**Extraire de SQL Server vers Excel**

```powershell
Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH' -Query 'SELECT TOP 1000 * FROM dbo.Ventes' |
    Export-ExcelSheet -Path .\rapport.xlsx -SheetName 'Ventes' -AutoFilter
```

**Comparer deux extractions**

```powershell
Compare-DataSet -Reference (Import-CsvFast .\avant.csv) `
                -Difference (Import-CsvFast .\apres.csv) `
                -KeyColumns 'ID' | Group-Object Statut
```

---

## Principes de conception

**Performance** — `List[T]` plutôt que `+=`, hashtables pour les jointures,
`StreamReader` sur les gros fichiers, lecture Excel en un seul appel COM,
regex compilées, `SqlBulkCopy` pour les chargements.

**Sécurité** — requêtes SQL toujours paramétrées (jamais de concaténation),
authentification Windows intégrée par défaut, `-WhatIf` sur toutes les opérations
destructrices, `-LiteralPath` systématique.

**Fiabilité** — validation des paramètres en entrée, libération des ressources
COM et SQL dans des blocs `finally`, syntaxe volontairement simple et explicite
plutôt que des constructions concises mais fragiles selon la version de PowerShell.

---

## Sécurité : les 3 réflexes

1. **`-WhatIf` avant toute opération destructrice**
   `Move-FileByRule`, `Remove-OldFile`, `Invoke-SqlNonQuery` le supportent tous.

2. **Jamais de valeur concaténée dans une requête SQL**
   Utilisez `-Parameters @{ cle = valeur }` — protège de l'injection SQL et gère
   correctement les apostrophes (`O'Brien`).

3. **`Backup-File` avant de modifier un fichier de production.**

---

## Résolution des problèmes courants

| Symptôme | Cause / solution |
|---|---|
| `n'est pas signé numériquement` | `Unblock-File -Path "C:\CRE\*.ps*"` |
| `l'exécution de scripts est désactivée` | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `Primitive JSON non valide` | BOM dans le fichier → utiliser `Read-TextFile` |
| Accents corrompus après export | Ajouter `-WithBom` à `Export-CsvFast` (pour Excel) |
| `EXCEL.EXE` reste en mémoire | Toujours `Close-ExcelApp` dans un `finally` |
| `1 + 1 = "11"` | `Import-Csv` renvoie du texte → `ConvertTo-TypedObject` |
| Script très lent | Chercher un `+=` dans une boucle → remplacer par `List[T]` |
| `OutOfMemoryException` sur Excel | Passer `-Mode CellByCell` (défaut) ou exporter en CSV |
| Module modifié non pris en compte | `Import-Module ... -Force` |
| Classe modifiée non prise en compte | Relancer complètement la session PowerShell |

---

## Parcours d'apprentissage suggéré

1. **Semaine 1** — `FORMATION-POWERSHELL.md` chapitres 1 à 7 (bases, pipeline, objets)
2. **Semaine 2** — chapitres 8 à 10 (fonctions, erreurs) + recettes 1 à 5
3. **Semaine 3** — chapitres 13 à 15 (fichiers, Excel, SQL) + recettes 6 à 11
4. **Ensuite** — chapitre 17 (performance) quand vos scripts ralentissent,
   chapitre 11 (POO) quand ils deviennent volumineux

Le chapitre 20 recense les pièges connus de PowerShell 5.1 : à parcourir dès que
quelque chose se comporte de façon inexplicable.
