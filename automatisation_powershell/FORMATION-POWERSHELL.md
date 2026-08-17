# Formation PowerShell — de zéro à l'automatisation ETL / Datawarehouse

> Public : débutant en PowerShell, à l'aise avec la logique de programmation.
> Contexte : poste **sans droits administrateur**, environnement verrouillé, missions ETL / DWH / SQL Server.
> Objectif : écrire des scripts fiables, performants et maintenables.

---

## Table des matières

1. [Comprendre ce qu'est PowerShell](#1-comprendre-ce-quest-powershell)
2. [Exécuter du code sans être administrateur](#2-exécuter-du-code-sans-être-administrateur)
3. [Variables et types](#3-variables-et-types)
4. [Opérateurs](#4-opérateurs)
5. [Structures de contrôle](#5-structures-de-contrôle)
6. [Le pipeline — le cœur de PowerShell](#6-le-pipeline--le-cœur-de-powershell)
7. [Les objets : PSCustomObject](#7-les-objets--pscustomobject)
8. [Les fonctions](#8-les-fonctions)
9. [Les fonctions avancées (cmdlets maison)](#9-les-fonctions-avancées-cmdlets-maison)
10. [La gestion des erreurs](#10-la-gestion-des-erreurs)
11. [Programmation orientée objet](#11-programmation-orientée-objet)
12. [Les modules : organiser son code](#12-les-modules--organiser-son-code)
13. [Fichiers texte, CSV, JSON, XML](#13-fichiers-texte-csv-json-xml)
14. [Excel via COM](#14-excel-via-com)
15. [SQL Server sans module ni admin](#15-sql-server-sans-module-ni-admin)
16. [Les expressions régulières](#16-les-expressions-régulières)
17. [Performance : les règles d'or](#17-performance--les-règles-dor)
18. [Sécurité et bonnes pratiques](#18-sécurité-et-bonnes-pratiques)
19. [Déboguer efficacement](#19-déboguer-efficacement)
20. [Pièges connus de PowerShell 5.1](#20-pièges-connus-de-powershell-51)

---

## 1. Comprendre ce qu'est PowerShell

La différence fondamentale avec `cmd`, `bash` ou un langage classique :

> **PowerShell manipule des objets, pas du texte.**

En bash, `ls | grep "csv"` traite des chaînes de caractères. En PowerShell,
`Get-ChildItem | Where-Object Extension -eq '.csv'` traite de véritables objets `FileInfo`
possédant des propriétés (`.Length`, `.LastWriteTime`) et des méthodes (`.Delete()`).

C'est ce qui le rend redoutable pour l'ETL : on chaîne des transformations d'objets structurés,
sans jamais parser du texte à la main.

### Les 3 briques de base

| Brique | Rôle | Exemple |
|---|---|---|
| **Cmdlet** | Commande native, toujours `Verbe-Nom` | `Get-Content`, `Import-Csv` |
| **Fonction** | Votre code réutilisable | `Get-MonRapport` |
| **Module** | Bibliothèque de fonctions | `PSToolkit.psm1` |

### Découvrir sans documentation (utile hors ligne)

```powershell
Get-Command -Noun Csv              # toutes les cmdlets agissant sur des CSV
Get-Help Import-Csv -Full          # aide complète
Get-Help Import-Csv -Examples      # juste les exemples (le plus utile)
Get-Member -InputObject $obj       # QUELLES propriétés/méthodes a cet objet ?
```

`Get-Member` est votre meilleur ami : il répond à « qu'est-ce que je manipule exactement ? ».

```powershell
Import-Csv .\data.csv | Get-Member      # montre les colonnes détectées
Get-ChildItem | Get-Member              # montre tout ce qu'un fichier expose
```

---

## 2. Exécuter du code sans être administrateur

**Bonne nouvelle : tout ce qui suit fonctionne en utilisateur standard.** Vous n'avez besoin de
droits admin que pour installer des modules *machine*, modifier `HKLM`, ou changer la politique
d'exécution globale — rien de tout cela n'est nécessaire ici.

### La politique d'exécution (ExecutionPolicy)

C'est le garde-fou qui empêche l'exécution de scripts. Trois solutions **sans admin** :

```powershell
# 1. Débloquer un fichier venant d'un téléchargement / GitHub (le plus courant)
Unblock-File -Path "C:\CRE\MonScript.ps1"

# 2. Contourner pour une seule exécution
powershell -ExecutionPolicy Bypass -File "C:\CRE\MonScript.ps1"

# 3. Changer la politique pour VOTRE compte uniquement (ne nécessite PAS d'admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

> Si `Get-ExecutionPolicy -List` montre une valeur imposée en scope `MachinePolicy` ou
> `UserPolicy`, c'est une GPO d'entreprise : elle prime sur tout, et il faut passer par l'IT.

### Installer un module sans admin

```powershell
Install-Module ImportExcel -Scope CurrentUser     # s'installe dans votre profil
```

En environnement hors ligne, cela échouera — d'où l'intérêt de la bibliothèque fournie,
qui n'utilise **que du .NET natif et COM**, sans aucune dépendance externe.

### Où PowerShell a le droit d'écrire

```powershell
$env:USERPROFILE      # C:\Users\vous          -> toujours accessible
$env:TEMP             # dossier temporaire     -> toujours accessible
$env:APPDATA          # config applicative     -> toujours accessible
```

---

## 3. Variables et types

### Déclaration

```powershell
$nom = "Franck"              # typage automatique (string)
$age = 42                    # int
[int]$compteur = 0           # typage explicite : rejette toute valeur non convertible
[string]$chemin = "C:\CRE"
```

Le typage explicite est **fortement recommandé** dans les scripts sérieux : il transforme une
erreur silencieuse en erreur immédiate.

### Types courants

```powershell
[string]   "texte"
[int]      42
[long]     9223372036854775807      # gros entiers (identifiants DWH)
[decimal]  10.5                     # précision exacte -> montants financiers
[double]   10.5                     # virgule flottante -> calculs scientifiques
[bool]     $true / $false
[datetime] Get-Date
[array]    @(1,2,3)
[hashtable] @{ cle = 'valeur' }
$null                               # absence de valeur
```

> **En ETL financier, utilisez `[decimal]`, jamais `[double]`** : `0.1 + 0.2` en double ne donne
> pas exactement `0.3`. Sur des montants, cela crée des écarts de rapprochement.

### Tableaux

```powershell
$tab = @('a', 'b', 'c')
$tab[0]                    # 'a'  (index 0-based)
$tab[-1]                   # 'c'  (dernier élément)
$tab[0..1]                 # 'a','b' (tranche)
$tab.Count                 # 3
$tab -contains 'b'         # $true
```

**Piège de performance majeur :**

```powershell
# LENT : recrée tout le tableau à chaque ajout -> O(n²)
$resultat = @()
foreach ($x in 1..50000) { $resultat += $x }        # plusieurs minutes !

# RAPIDE : liste .NET redimensionnable -> O(n)
$resultat = New-Object 'System.Collections.Generic.List[object]'
foreach ($x in 1..50000) { $resultat.Add($x) }      # instantané
```

Retenez cette règle : **jamais de `+=` sur un tableau dans une boucle.**

### Hashtables (dictionnaires)

Structure clé/valeur, avec accès en **O(1)** — indispensable pour les jointures ETL.

```powershell
$config = @{
    Serveur = 'SRVSQL01'
    Base    = 'DWH_PROD'
    Timeout = 30
}
$config['Serveur']              # lecture
$config.Serveur                 # lecture (syntaxe pointée)
$config['Env'] = 'PROD'         # ajout
$config.ContainsKey('Base')     # $true
$config.Remove('Timeout')

foreach ($cle in $config.Keys) {
    Write-Host ("{0} = {1}" -f $cle, $config[$cle])
}
```

**Cas d'usage ETL décisif — la jointure rapide :**

```powershell
# Objectif : enrichir 100 000 lignes avec un référentiel de 10 000 lignes.
# Approche naïve (double boucle) = 1 milliard de comparaisons -> des heures.
# Approche hashtable = 110 000 opérations -> quelques secondes.

$refIndex = @{}
foreach ($r in Import-Csv .\referentiel.csv) { $refIndex[$r.Code] = $r }

foreach ($ligne in Import-Csv .\donnees.csv) {
    $ref = $refIndex[$ligne.Code]          # accès instantané
    if ($ref) { $ligne | Add-Member -NotePropertyName 'Libelle' -NotePropertyValue $ref.Libelle }
}
```

### Portée des variables (scope)

```powershell
$global:x    # visible partout dans la session — à éviter
$script:x    # visible dans tout le script — utile pour un compteur/log
$local:x     # visible dans le bloc courant (défaut)
```

Par défaut, une fonction **lit** les variables du parent mais ne peut pas les **modifier**.
Pour un compteur partagé, utilisez `$script:`.

---

## 4. Opérateurs

PowerShell n'utilise pas `==`, `>`, `&&` comme les autres langages. C'est déroutant au début.

### Comparaison

| Opérateur | Sens | Exemple |
|---|---|---|
| `-eq` | égal | `$a -eq 5` |
| `-ne` | différent | `$a -ne 5` |
| `-gt` / `-ge` | supérieur / ou égal | `$a -gt 5` |
| `-lt` / `-le` | inférieur / ou égal | `$a -lt 5` |
| `-like` | joker `*` `?` | `$f -like '*.csv'` |
| `-notlike` | négation | `$f -notlike 'tmp*'` |
| `-match` | expression régulière | `$s -match '^\d{4}$'` |
| `-notmatch` | négation regex | |
| `-contains` | le tableau contient l'élément | `$tab -contains 'a'` |
| `-in` | l'élément est dans le tableau | `'a' -in $tab` |
| `-is` | test de type | `$x -is [int]` |

> **Important :** par défaut, les comparaisons de chaînes sont **insensibles à la casse**.
> Préfixez par `c` pour forcer la sensibilité (`-ceq`, `-clike`, `-cmatch`).

### Logiques

```powershell
-and   -or   -not   -xor
if ($a -gt 0 -and $b -lt 10) { }
if (-not $trouve) { }
```

### Opérateurs de texte très utiles

```powershell
"a,b,c" -split ','                  # tableau : a, b, c
@('a','b') -join ' | '              # chaîne  : "a | b"
"Bonjour" -replace 'jour', 'soir'   # "Bonsoir"  (regex acceptée)

# L'opérateur -f (format) : PRÉFÉREZ-LE à la concaténation par +
$msg = "Fichier {0} : {1} lignes en {2:N1}s" -f $nom, $count, $duree
```

> **Règle de fiabilité :** utilisez `-f` plutôt que `+` pour construire des chaînes.
> L'opérateur `+` en PowerShell est polymorphe (addition, concaténation, fusion de tableaux)
> et provoque des erreurs `op_Addition` déroutantes quand un opérande n'a pas le type attendu.

### Redirection et opérateurs spéciaux

```powershell
$obj?.Propriete           # accès sécurisé si $obj est $null (PowerShell 7+ uniquement)
$a ?? 'defaut'            # valeur par défaut si $null (PowerShell 7+ uniquement)

# Équivalent compatible PowerShell 5.1 :
$valeur = if ($null -ne $a) { $a } else { 'defaut' }
```

---

## 5. Structures de contrôle

### Conditions

```powershell
if ($count -eq 0) {
    Write-Host "Aucune donnée"
}
elseif ($count -lt 100) {
    Write-Host "Peu de données"
}
else {
    Write-Host "Volume normal"
}

# switch : plus lisible que des elseif en cascade
switch ($extension) {
    '.csv'  { Import-Csv $f;        break }
    '.json' { Get-Content $f | ConvertFrom-Json; break }
    '.xlsx' { Import-ExcelSheet $f; break }
    default { Write-Warning "Format non géré : $extension" }
}

# switch avec regex et joker
switch -Regex ($ligne) {
    '^ERROR'   { $erreurs++ }
    '^WARN'    { $avertissements++ }
}
```

> **Piège classique :** pour tester le `$null`, mettez `$null` **à gauche** :
> `if ($null -eq $x)` et non `if ($x -eq $null)`. Si `$x` est un tableau, la seconde forme
> filtre le tableau au lieu de renvoyer un booléen.

### Boucles

```powershell
# foreach : la plus lisible, la plus utilisée
foreach ($fichier in $liste) { ... }

# for : quand on a besoin de l'index
for ($i = 0; $i -lt $tab.Count; $i++) { ... }

# while / do-while
while ($ligne = $reader.ReadLine()) { ... }
do { ... } while ($condition)

# ForEach-Object : version pipeline (traite au fil de l'eau, économe en mémoire)
Get-ChildItem *.csv | ForEach-Object { Write-Host $_.Name }
```

**`foreach` vs `ForEach-Object` — le choix compte :**

| | `foreach ($x in $y)` | `$y | ForEach-Object` |
|---|---|---|
| Vitesse | **Plus rapide** | Plus lent (surcoût pipeline) |
| Mémoire | Charge tout en mémoire | **Traite au fil de l'eau** |
| Quand | Collection déjà en mémoire | Gros volumes, flux continu |

Sur un fichier de 5 Go, `ForEach-Object` en pipeline évite de saturer la RAM.

### Contrôle de flux

```powershell
break        # sort de la boucle
continue     # passe à l'itération suivante
return       # sort de la fonction
```

---

## 6. Le pipeline — le cœur de PowerShell

Le pipeline `|` passe les objets d'une commande à la suivante.

```powershell
Get-ChildItem -Path C:\Data -Filter *.csv |
    Where-Object   { $_.Length -gt 1MB } |
    Sort-Object     LastWriteTime -Descending |
    Select-Object   -First 5 Name, Length, LastWriteTime
```

`$_` (ou `$PSItem`) représente **l'objet courant** dans le pipeline.

### Les cmdlets de pipeline à connaître par cœur

```powershell
Where-Object    # filtrer      (SQL : WHERE)
Select-Object   # projeter     (SQL : SELECT)
Sort-Object     # trier        (SQL : ORDER BY)
Group-Object    # regrouper    (SQL : GROUP BY)
Measure-Object  # agréger      (SQL : COUNT/SUM/AVG)
ForEach-Object  # transformer
Select-Object -Unique   # dédoublonner (SQL : DISTINCT)
```

### Équivalences SQL ↔ PowerShell (très utile en ETL)

```powershell
# SELECT Region, COUNT(*), SUM(Montant) FROM ventes GROUP BY Region HAVING COUNT(*) > 10
Import-Csv .\ventes.csv |
    Group-Object Region |
    Where-Object { $_.Count -gt 10 } |
    ForEach-Object {
        [PSCustomObject]@{
            Region = $_.Name
            Nb     = $_.Count
            Total  = ($_.Group | Measure-Object Montant -Sum).Sum
        }
    }

# SELECT DISTINCT Code FROM data
Import-Csv .\data.csv | Select-Object -ExpandProperty Code -Unique

# Colonnes calculées
Import-Csv .\data.csv | Select-Object Nom,
    @{ Name = 'MontantTTC'; Expression = { [decimal]$_.MontantHT * 1.2 } }
```

La syntaxe `@{ Name = ...; Expression = { ... } }` s'appelle une **propriété calculée**.
C'est l'équivalent d'un `AS` en SQL.

### Filtrer tôt = filtrer vite

```powershell
# LENT : récupère tout puis filtre
Get-ChildItem -Recurse | Where-Object { $_.Extension -eq '.csv' }

# RAPIDE : le filtre est appliqué par le fournisseur, à la source
Get-ChildItem -Recurse -Filter *.csv
```

Règle générale : **utilisez les paramètres natifs de filtrage (`-Filter`) avant `Where-Object`.**

---

## 7. Les objets : PSCustomObject

C'est **la** structure de données à utiliser pour représenter une ligne de données.

```powershell
$ligne = [PSCustomObject]@{
    Code      = 'CLI001'
    Libelle   = 'Client Alpha'
    Montant   = [decimal]1250.50
    DateMaj   = Get-Date
}

$ligne.Code                    # lecture
$ligne.Montant = 1300          # modification
```

Un tableau de `PSCustomObject` s'exporte directement, sans conversion :

```powershell
$lignes | Export-Csv .\sortie.csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
$lignes | ConvertTo-Json -Depth 5 | Set-Content .\sortie.json
$lignes | Format-Table -AutoSize
$lignes | Out-GridView                 # fenêtre interactive de tri/filtre !
```

### Ajouter une propriété dynamiquement

```powershell
$ligne | Add-Member -NotePropertyName 'Statut' -NotePropertyValue 'OK'
```

### Pourquoi PSCustomObject et pas une hashtable ?

| | Hashtable | PSCustomObject |
|---|---|---|
| Ordre des clés | Non garanti | **Garanti** |
| Export CSV | Ne marche pas directement | **Direct** |
| Affichage tableau | Mauvais | **Propre** |
| Accès par clé variable | `$h[$k]` | `$o.$k` (fonctionne aussi) |

**Conclusion : hashtable pour un index/dictionnaire, PSCustomObject pour une ligne de données.**

---

## 8. Les fonctions

```powershell
function Get-Doublons {
    param(
        [string[]]$Valeurs
    )

    $vus = New-Object 'System.Collections.Generic.HashSet[string]'
    $doublons = New-Object 'System.Collections.Generic.List[string]'

    foreach ($v in $Valeurs) {
        if (-not $vus.Add($v)) { $doublons.Add($v) }   # .Add renvoie $false si déjà présent
    }
    return $doublons
}

$d = Get-Doublons -Valeurs @('a','b','a','c','b')     # a, b
```

### Piège n°1 des fonctions PowerShell : la sortie implicite

**Toute expression non capturée est renvoyée par la fonction**, pas seulement le `return`.

```powershell
function Test-Mauvais {
    $liste = New-Object 'System.Collections.Generic.List[int]'
    $liste.Add(1)          # ATTENTION : .Add() renvoie parfois une valeur -> polluée !
    return $liste
}
```

**Solutions :**

```powershell
$liste.Add(1) | Out-Null          # rediriger vers le néant
[void]$liste.Add(1)               # caster en void (plus rapide, préféré)
$null = $liste.Add(1)             # affecter à $null
```

C'est la source n°1 de bugs « ma fonction renvoie n'importe quoi ».

### Appeler une fonction : jamais de parenthèses

```powershell
Get-Doublons -Valeurs $tab          # CORRECT
Get-Doublons($tab)                  # FAUX : passe un tableau comme 1er argument positionnel
Ma-Fonction -A 1 -B 2               # CORRECT
Ma-Fonction(1, 2)                   # FAUX : passe UN tableau à $A, $B reste vide
```

---

## 9. Les fonctions avancées (cmdlets maison)

Ajoutez `[CmdletBinding()]` pour transformer votre fonction en véritable cmdlet : elle gagne
automatiquement `-Verbose`, `-Debug`, `-ErrorAction`, `-WhatIf`…

```powershell
function Import-DataFile {
    <#
    .SYNOPSIS
        Importe un fichier de données et renvoie des objets.
    .DESCRIPTION
        Détecte le format d'après l'extension et applique le bon importateur.
    .PARAMETER Path
        Chemin du fichier à importer.
    .EXAMPLE
        Import-DataFile -Path .\clients.csv
    #>
    [CmdletBinding()]
    param(
        # Obligatoire, accepte l'entrée pipeline
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        # Valeurs autorisées uniquement
        [ValidateSet(';', ',', "`t", '|')]
        [string]$Delimiter = ';',

        # Bornes numériques
        [ValidateRange(1, 1000000)]
        [int]$MaxRows = 100000,

        # Validation personnalisée
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigFile,

        # Interrupteur (présent = $true)
        [switch]$SkipHeader
    )

    begin {
        # Exécuté UNE FOIS avant le pipeline : initialisation
        Write-Verbose "Début de l'import"
        $total = 0
    }

    process {
        # Exécuté POUR CHAQUE objet reçu du pipeline
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Error "Fichier introuvable : $Path"
            return
        }
        Import-Csv -LiteralPath $Path -Delimiter $Delimiter
        $total++
    }

    end {
        # Exécuté UNE FOIS après : bilan, nettoyage
        Write-Verbose "Terminé : $total fichier(s)"
    }
}
```

### Les attributs de validation (à utiliser systématiquement)

| Attribut | Rôle |
|---|---|
| `[Parameter(Mandatory=$true)]` | Paramètre obligatoire |
| `[ValidateNotNullOrEmpty()]` | Refuse `$null` et `''` |
| `[ValidateSet('A','B')]` | Liste fermée de valeurs |
| `[ValidateRange(1,100)]` | Bornes numériques |
| `[ValidatePattern('^\d{4}$')]` | Conformité regex |
| `[ValidateScript({ ... })]` | Test personnalisé |
| `[ValidateCount(1,5)]` | Nombre d'éléments d'un tableau |

**Ces validations sont votre première ligne de défense** : elles bloquent une mauvaise donnée
à l'entrée, avant qu'elle ne corrompe un traitement de 2 heures.

### Sécuriser les opérations destructrices : -WhatIf

```powershell
function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$Path, [int]$DaysOld = 30)

    $limite = (Get-Date).AddDays(-$DaysOld)
    foreach ($f in Get-ChildItem -LiteralPath $Path -File) {
        if ($f.LastWriteTime -lt $limite) {
            if ($PSCmdlet.ShouldProcess($f.FullName, 'Supprimer')) {
                Remove-Item -LiteralPath $f.FullName -Force
            }
        }
    }
}

Remove-OldFiles -Path C:\Temp -WhatIf     # SIMULE sans rien supprimer
```

> **Adoptez ce réflexe** : toute fonction qui supprime, écrase ou déplace doit supporter `-WhatIf`.
> C'est ce qui vous évitera d'effacer un répertoire de production.

---

## 10. La gestion des erreurs

### Les deux natures d'erreur

| Type | Comportement | Interceptable par try/catch |
|---|---|---|
| **Terminating** | Arrête le script | Oui |
| **Non-terminating** | Affiche et continue | **Non**, sauf avec `-ErrorAction Stop` |

La plupart des erreurs de cmdlets sont **non-terminating** : d'où le piège du `try/catch` qui
« ne marche pas ».

```powershell
# NE FONCTIONNE PAS : Get-Content lève une erreur non-terminating
try { Get-Content "inexistant.txt" } catch { Write-Host "Attrapé" }

# FONCTIONNE
try { Get-Content "inexistant.txt" -ErrorAction Stop } catch { Write-Host "Attrapé" }
```

### La solution globale

```powershell
$ErrorActionPreference = 'Stop'     # en tête de script : TOUT devient terminating
```

C'est le réglage recommandé pour un script ETL : mieux vaut s'arrêter net que produire un
fichier de sortie silencieusement incomplet.

### try / catch / finally

```powershell
try {
    $conn.Open()
    $data = Invoke-Query -Sql $requete
}
catch [System.Data.SqlClient.SqlException] {
    # Catch typé : ne capture QUE les erreurs SQL
    Write-Error ("Erreur SQL {0} : {1}" -f $_.Exception.Number, $_.Exception.Message)
    throw
}
catch {
    # Catch générique : tout le reste
    Write-Error ("Erreur inattendue : {0}" -f $_.Exception.Message)
    throw
}
finally {
    # TOUJOURS exécuté, erreur ou non -> libération des ressources
    if ($conn -and $conn.State -eq 'Open') { $conn.Close() }
}
```

> **Le bloc `finally` est non négociable** dès que vous ouvrez une connexion SQL, un fichier
> ou une instance Excel COM. Sans lui, un plantage laisse un processus `EXCEL.EXE` fantôme
> ou une connexion ouverte.

### Exploiter l'objet erreur

```powershell
catch {
    $_.Exception.Message              # message
    $_.Exception.GetType().FullName   # type .NET exact
    $_.InvocationInfo.ScriptLineNumber # LIGNE du script en cause
    $_.InvocationInfo.Line            # code source de la ligne
    $_.ScriptStackTrace               # pile d'appel complète
}
```

Ces informations sont précieuses quand le débogage se fait à distance (capture d'écran, log).

### Écrire des messages

```powershell
Write-Host "Message"                  # console uniquement (non capturable dans le pipeline)
Write-Output $objet                   # SORTIE de la fonction (pipeline)
Write-Verbose "Détail"                # visible avec -Verbose
Write-Warning "Attention"             # jaune
Write-Error "Erreur"                  # rouge, non-terminating
throw "Erreur fatale"                 # rouge, terminating
Write-Progress -Activity "..." -PercentComplete 50   # barre de progression
```

> **Ne jamais utiliser `Write-Host` pour renvoyer une donnée** : elle n'entre pas dans le
> pipeline et sera perdue. `Write-Host` = affichage humain, `Write-Output` = donnée.

---

## 11. Programmation orientée objet

**Oui, PowerShell 5.0+ supporte de vraies classes** avec héritage, interfaces, membres statiques,
constructeurs et encapsulation.

### Classe de base

```powershell
class Client {
    # --- Propriétés (typées) ---
    [string]  $Code
    [string]  $Nom
    [decimal] $ChiffreAffaires
    [datetime]$DateCreation
    hidden [string] $NoteInterne          # 'hidden' : masquée à l'affichage/Get-Member

    # --- Constructeurs (surcharges autorisées) ---
    Client() {
        $this.DateCreation = Get-Date
    }

    Client([string]$code, [string]$nom) {
        $this.Code = $code
        $this.Nom  = $nom
        $this.DateCreation = Get-Date
    }

    # --- Méthodes ---
    [bool] EstActif() {
        return $this.ChiffreAffaires -gt 0
    }

    [void] AppliquerRemise([decimal]$taux) {
        if ($taux -lt 0 -or $taux -gt 1) {
            throw "Taux invalide : doit être entre 0 et 1"
        }
        $this.ChiffreAffaires = $this.ChiffreAffaires * (1 - $taux)
    }

    # Surcharge de l'affichage (équivalent ToString() en C#)
    [string] ToString() {
        return ("{0} - {1} ({2:N2} EUR)" -f $this.Code, $this.Nom, $this.ChiffreAffaires)
    }

    # --- Membre statique (appartient à la classe, pas à l'instance) ---
    static [int] $NombreClients = 0

    static [Client] Creer([string]$code, [string]$nom) {
        [Client]::NombreClients++
        return [Client]::new($code, $nom)
    }
}
```

**Utilisation :**

```powershell
$c = [Client]::new('CLI001', 'Alpha')
$c.ChiffreAffaires = 10000
$c.EstActif()                      # True
$c.AppliquerRemise(0.1)            # 9000
$c.ToString()                      # "CLI001 - Alpha (9 000,00 EUR)"

[Client]::NombreClients            # membre statique
$c2 = [Client]::Creer('CLI002', 'Beta')    # fabrique statique
```

> **Important dans les méthodes de classe :** contrairement aux fonctions, une méthode typée
> `[void]` ne renvoie rien et une méthode typée `[bool]` **doit** avoir un `return` explicite.
> Il n'y a pas de sortie implicite ici — c'est plus sûr que les fonctions.

### Héritage

```powershell
class ClientPro : Client {
    [string] $Siret
    [int]    $NombreSalaries

    # Appel du constructeur parent avec : base(...)
    ClientPro([string]$code, [string]$nom, [string]$siret) : base($code, $nom) {
        $this.Siret = $siret
    }

    # Redéfinition (override) d'une méthode du parent
    [string] ToString() {
        return ("{0} [SIRET {1}]" -f ([Client]$this).ToString(), $this.Siret)
    }

    # Méthode propre à la classe fille
    [bool] EstPME() {
        return $this.NombreSalaries -lt 250
    }
}

$p = [ClientPro]::new('PRO001', 'Gamma SARL', '12345678900012')
$p -is [Client]        # True : le polymorphisme fonctionne
```

### Classe abstraite et interface (via une classe de base)

PowerShell n'a pas le mot-clé `abstract`, mais on simule :

```powershell
class EtapeEtl {
    [string] $Nom
    [int]    $LignesTraitees = 0

    # "Abstraite" : lève une erreur si non redéfinie
    [void] Executer() {
        throw "La méthode Executer() doit être implémentée par la classe fille"
    }

    # Méthode concrète héritée par toutes les étapes
    [void] Journaliser([string]$message) {
        Write-Host ("[{0}] {1} : {2}" -f (Get-Date -Format 'HH:mm:ss'), $this.Nom, $message)
    }
}

class EtapeExtraction : EtapeEtl {
    [string] $Source

    EtapeExtraction([string]$source) {
        $this.Nom = 'EXTRACTION'
        $this.Source = $source
    }

    [void] Executer() {
        $this.Journaliser("Lecture de $($this.Source)")
        $this.LignesTraitees = (Import-Csv $this.Source).Count
        $this.Journaliser("$($this.LignesTraitees) lignes lues")
    }
}

# Pipeline ETL polymorphe
$pipeline = @(
    [EtapeExtraction]::new('C:\data\source.csv'),
    [EtapeTransformation]::new(),
    [EtapeChargement]::new('DWH_PROD')
)
foreach ($etape in $pipeline) { $etape.Executer() }    # polymorphisme
```

C'est exactement le patron qu'il vous faut pour industrialiser vos traitements ETL.

### Énumérations

```powershell
enum StatutCre {
    Valide   = 1
    Invalide = 2
    EnAttente = 3
}

enum TypeCre {
    Complet
    Differentiel
}

$s = [StatutCre]::Valide
$s -eq [StatutCre]::Valide         # True
[StatutCre]::Valide.value__        # 1
[enum]::GetNames([StatutCre])      # Valide, Invalide, EnAttente
```

Les énumérations remplacent avantageusement les chaînes magiques : une faute de frappe devient
une erreur de compilation au lieu d'un bug silencieux.

### Validation dans le constructeur (encapsulation)

```powershell
class ConnexionDwh {
    [string] $Serveur
    [string] $Base
    hidden [string] $ChaineConnexion

    ConnexionDwh([string]$serveur, [string]$base) {
        if ([string]::IsNullOrWhiteSpace($serveur)) { throw "Serveur obligatoire" }
        if ([string]::IsNullOrWhiteSpace($base))    { throw "Base obligatoire" }

        $this.Serveur = $serveur
        $this.Base    = $base
        # Authentification Windows intégrée : aucun mot de passe stocké
        $this.ChaineConnexion = "Server=$serveur;Database=$base;Integrated Security=True;"
    }

    [string] GetChaine() { return $this.ChaineConnexion }
}
```

### Limites à connaître

- Les classes doivent être définies **avant** utilisation dans le fichier (pas de forward reference).
- Dans un module, exportez-les via `using module MonModule` (et non `Import-Module`).
- Modifier une classe nécessite de **relancer la session PowerShell** (les classes sont mises en cache).
- Pas de surcharge d'opérateurs, pas de propriétés calculées avec `get`/`set` (PowerShell 5.1).

### Quand utiliser une classe plutôt qu'un PSCustomObject ?

| Situation | Choix |
|---|---|
| Ligne de données simple | `PSCustomObject` |
| Structure avec règles métier / validation | **Classe** |
| Héritage, polymorphisme (étapes ETL) | **Classe** |
| Export CSV/JSON direct | `PSCustomObject` |
| Volume énorme (millions d'objets) | `PSCustomObject` (plus léger) |

---

## 12. Les modules : organiser son code

Un module `.psm1` est simplement un fichier contenant des fonctions.

```powershell
# Charger le module
Import-Module C:\CRE\PSToolkit.psm1 -Force      # -Force recharge après modification

# Lister ce qu'il expose
Get-Command -Module PSToolkit

# Aide d'une fonction
Get-Help Import-CsvFast -Full
```

Dans le module, on contrôle ce qui est public :

```powershell
function Get-Interne { }        # non exportée -> privée
function Get-Publique { }
Export-ModuleMember -Function 'Get-Publique', 'Import-*'
```

> Sur un poste verrouillé, `Import-Module` avec un **chemin complet** fonctionne toujours,
> sans installation ni droits particuliers.

---

## 13. Fichiers texte, CSV, JSON, XML

### Lire un fichier texte

```powershell
# Petit fichier : tout en mémoire, simple
$contenu = Get-Content -LiteralPath $f -Raw                  # une seule chaîne
$lignes  = Get-Content -LiteralPath $f                       # tableau de lignes

# GROS fichier (> 100 Mo) : lecture en flux, mémoire constante
$reader = [System.IO.StreamReader]::new($f, [System.Text.Encoding]::UTF8)
try {
    while ($null -ne ($ligne = $reader.ReadLine())) {
        # traiter $ligne
    }
}
finally { $reader.Dispose() }
```

**Sur un fichier de 2 Go, `Get-Content` sature la RAM ; `StreamReader` la maintient constante.**

### Le problème de l'encodage (crucial en ETL français)

```powershell
# Toujours préciser l'encodage explicitement
Get-Content -LiteralPath $f -Encoding UTF8
Set-Content -LiteralPath $f -Value $txt -Encoding UTF8

# PowerShell 5.1 : 'UTF8' ÉCRIT UN BOM. Pour un UTF-8 sans BOM (attendu par SQL Server, Unix) :
[System.IO.File]::WriteAllText($f, $txt, [System.Text.UTF8Encoding]::new($false))

# Lire en gérant automatiquement le BOM
$txt = [System.IO.File]::ReadAllText($f)
```

> **Le BOM (Byte Order Mark)** est la cause n°1 des erreurs « caractère invalide en début de
> fichier » lors des imports SQL Server / `ConvertFrom-Json`. Utilisez `ReadAllText`/`WriteAllText`
> pour le contrôler.

Encodages fréquents en France : `UTF8`, `Default` (= ANSI/Windows-1252), `Latin1` (ISO-8859-1).

### CSV

```powershell
# Import : détecte les colonnes, renvoie des PSCustomObject
$data = Import-Csv -LiteralPath .\clients.csv -Delimiter ';' -Encoding UTF8

# Export
$data | Export-Csv -LiteralPath .\sortie.csv -Delimiter ';' -NoTypeInformation -Encoding UTF8

# Conversion sans fichier
$csvTexte = $data | ConvertTo-Csv -NoTypeInformation -Delimiter ';'
$objets   = $csvTexte | ConvertFrom-Csv -Delimiter ';'
```

> `-NoTypeInformation` est **indispensable** : sans lui, PowerShell 5.1 ajoute une ligne
> `#TYPE System.Management.Automation.PSCustomObject` en tête, qui casse tous les imports.

**Attention aux types :** `Import-Csv` renvoie **tout en chaîne de caractères**.

```powershell
$data[0].Montant + 100        # "1250100" -> concaténation, pas addition !
[decimal]$data[0].Montant + 100   # 1350 -> correct
```

D'où l'intérêt d'une conversion typée explicite après import (voir la fonction
`ConvertTo-TypedObject` dans la bibliothèque).

### JSON

```powershell
$obj = Get-Content .\config.json -Raw | ConvertFrom-Json
$obj = [System.IO.File]::ReadAllText('.\config.json') | ConvertFrom-Json   # gère le BOM

$obj | ConvertTo-Json -Depth 10 | Set-Content .\out.json -Encoding UTF8
```

> `-Depth` vaut **2 par défaut** : au-delà, les objets imbriqués sont tronqués en
> `System.Object[]`. Mettez toujours `-Depth 10` pour être tranquille.

### XML

```powershell
[xml]$xml = Get-Content .\config.xml -Raw
$xml.configuration.appSettings.add            # navigation par propriétés
$xml.SelectNodes('//table[@name="clients"]')  # XPath
$xml.Save('C:\sortie.xml')
```

### Fichiers à largeur fixe (mainframe, exports COBOL)

```powershell
foreach ($ligne in [System.IO.File]::ReadLines($f)) {
    [PSCustomObject]@{
        Code    = $ligne.Substring(0, 10).Trim()
        Libelle = $ligne.Substring(10, 40).Trim()
        Montant = [decimal]$ligne.Substring(50, 12).Trim()
    }
}
```

---

## 14. Excel via COM

**Sans admin et sans module externe**, on pilote l'Excel installé sur le poste.

### Le squelette obligatoire

```powershell
$excel = $null; $wb = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible       = $false
    $excel.DisplayAlerts = $false
    $excel.ScreenUpdating = $false        # accélère fortement
    $excel.EnableEvents   = $false

    $wb = $excel.Workbooks.Open($chemin, 0, $false)
    $ws = $wb.Worksheets.Item('Feuil1')

    # ... traitement ...

    $wb.Save()
}
finally {
    # OBLIGATOIRE : sinon EXCEL.EXE reste en mémoire indéfiniment
    if ($wb)    { $wb.Close($false) | Out-Null }
    if ($excel) { $excel.Quit() }
    foreach ($o in @($wb, $excel)) {
        if ($o) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
```

### Lecture performante : un seul aller-retour COM

Chaque accès COM (`Cells.Item(r,c)`) coûte cher. Sur 100 000 cellules, c'est catastrophique.

```powershell
# LENT : 100 000 appels COM -> plusieurs minutes
for ($r = 1; $r -le 1000; $r++) {
    for ($c = 1; $c -le 100; $c++) { $v = $ws.Cells.Item($r, $c).Value2 }
}

# RAPIDE : 1 appel COM, tout arrive en mémoire -> < 1 seconde
$data = $ws.UsedRange.Value2          # tableau 2D
```

### Manipuler le tableau 2D renvoyé

Le tableau renvoyé par Excel est **1-based** (et non 0-based comme les tableaux PowerShell).

```powershell
$rMin = $data.GetLowerBound(0); $rMax = $data.GetUpperBound(0)
$cMin = $data.GetLowerBound(1); $cMax = $data.GetUpperBound(1)

for ($r = $rMin; $r -le $rMax; $r++) {
    $valeur = $data.GetValue($r, 1)          # préférez .GetValue(...)
}
```

> **Règle de fiabilité éprouvée :** utilisez `.GetValue(r, c)` et `.SetValue(v, r, c)` plutôt que
> la syntaxe `$data[$r, $c]`. Cette dernière est ambiguë pour l'analyseur PowerShell selon les
> versions et provoque des erreurs `op_Addition` incompréhensibles en écriture.

### Écriture

```powershell
# Petites quantités ou fiabilité maximale : cellule par cellule
$ws.Cells.Item($r, $c).Value2 = $valeur

# Gros volumes : écriture par blocs (plus rapide mais plus fragile en COM)
$plage = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item($n,3))
$plage.Value2 = $tableau2D
```

> Si une écriture en bloc lève un `OutOfMemoryException` sur un petit volume, ce n'est pas un
> vrai manque de mémoire : c'est une erreur générique de marshaling COM. Repliez-vous sur
> l'écriture cellule par cellule, ou exportez en CSV puis ouvrez le CSV avec Excel.

### Alternative sans Excel installé : OleDb

```powershell
$cs = "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$chemin;Extended Properties='Excel 12.0 Xml;HDR=YES';"
# Permet de requêter un .xlsx en SQL, sans lancer Excel
# Nécessite le pilote ACE (souvent déjà présent avec Office)
```

---

## 15. SQL Server sans module ni admin

`Invoke-Sqlcmd` exige le module `SqlServer` (installation souvent impossible). La solution
universelle : **`System.Data.SqlClient`**, présent nativement dans .NET Framework.

```powershell
function Invoke-SqlQuery {
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 120
    )

    # Authentification Windows : aucun mot de passe à stocker
    $cs = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=15;"
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText    = $Query
        $cmd.CommandTimeout = $TimeoutSeconds

        # PARAMÈTRES : protection contre l'injection SQL
        foreach ($k in $Parameters.Keys) {
            [void]$cmd.Parameters.AddWithValue("@$k", $Parameters[$k])
        }

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $table   = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return $table
    }
    finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
        $conn.Dispose()
    }
}

# Usage
$r = Invoke-SqlQuery -Server 'SRVSQL01' -Database 'DWH' `
     -Query 'SELECT * FROM dbo.Clients WHERE Region = @reg' `
     -Parameters @{ reg = 'IDF' }
```

> **Ne concaténez JAMAIS une valeur dans une requête SQL.** Utilisez toujours des paramètres.
> `"WHERE Nom = '$nom'"` est une faille d'injection SQL, même en interne : il suffit d'une
> apostrophe dans une donnée (`O'Brien`) pour casser le traitement.

### Insertion massive (SqlBulkCopy) — indispensable en DWH

```powershell
$bulk = New-Object System.Data.SqlClient.SqlBulkCopy($cs)
$bulk.DestinationTableName = 'dbo.Staging_Clients'
$bulk.BatchSize = 5000
$bulk.BulkCopyTimeout = 600
$bulk.WriteToServer($dataTable)      # des millions de lignes en quelques secondes
$bulk.Close()
```

C'est **100 à 1000 fois plus rapide** qu'une boucle d'`INSERT`.

---

## 16. Les expressions régulières

Omniprésentes en ETL : parsing de logs, extraction depuis du SQL, validation de formats.

```powershell
# Test
if ($ligne -match '^(\d{4})-(\d{2})-(\d{2})') {
    $annee = $Matches[1]     # groupes capturés
    $mois  = $Matches[2]
}

# Remplacement
$propre = $texte -replace '\s+', ' '            # espaces multiples -> un seul

# Toutes les occurrences
$rx = [regex]::new('TABLE\s+(\w+)', 'IgnoreCase')
foreach ($m in $rx.Matches($sql)) { $m.Groups[1].Value }
```

### Regex compilée : indispensable en boucle

```powershell
# LENT : la regex est recompilée à chaque itération
foreach ($l in $lignes) { if ($l -match $motif) { } }

# RAPIDE : compilée une seule fois
$rx = [regex]::new($motif, [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')
foreach ($l in $lignes) { if ($rx.IsMatch($l)) { } }
```

> **Syntaxe fiable des options :** utilisez la forme chaîne `[RegexOptions]'IgnoreCase, Compiled'`
> plutôt que `-bor` avec des continuations de ligne, source d'erreurs de parsing.

### Aide-mémoire

| Motif | Sens |
|---|---|
| `\d` `\w` `\s` | chiffre / alphanumérique / espace |
| `\D` `\W` `\S` | négations |
| `^` `$` | début / fin de ligne |
| `\b` | limite de mot |
| `*` `+` `?` | 0+ / 1+ / 0 ou 1 |
| `{2,5}` | entre 2 et 5 fois |
| `(...)` | groupe capturant |
| `(?:...)` | groupe non capturant |
| `(?<nom>...)` | groupe nommé |
| `(?=...)` `(?!...)` | assertion avant / négative |
| `\|` | alternative |

---

## 17. Performance : les règles d'or

| # | Règle | Gain typique |
|---|---|---|
| 1 | `List<T>` au lieu de `+=` sur tableau | ×100 à ×1000 |
| 2 | Hashtable pour les jointures/recherches | ×100 à ×10000 |
| 3 | `StringBuilder` au lieu de `+=` sur chaîne | ×50 |
| 4 | Lecture Excel en bloc (`UsedRange.Value2`) | ×100 |
| 5 | Regex compilée hors boucle | ×5 à ×10 |
| 6 | `-Filter` natif plutôt que `Where-Object` | ×5 |
| 7 | `StreamReader` sur les gros fichiers | mémoire constante |
| 8 | `SqlBulkCopy` au lieu d'`INSERT` en boucle | ×100 à ×1000 |
| 9 | `foreach` plutôt que `ForEach-Object` (si tout tient en RAM) | ×2 à ×5 |
| 10 | `[void]` plutôt que `| Out-Null` | ×2 sur boucles serrées |

### StringBuilder

```powershell
$sb = New-Object System.Text.StringBuilder
foreach ($l in $lignes) { [void]$sb.AppendLine($l) }
$resultat = $sb.ToString()
```

### HashSet pour les dédoublonnages et appartenances

```powershell
$vus = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($c in $codes) {
    if (-not $vus.Add($c)) { Write-Warning "Doublon : $c" }   # .Add renvoie $false si déjà là
}
```

### Mesurer plutôt que supposer

```powershell
Measure-Command { ...votre code... }

# Comparaison A/B
$a = Measure-Command { $r = @();  foreach ($i in 1..20000) { $r += $i } }
$b = Measure-Command { $r = New-Object 'System.Collections.Generic.List[int]'
                       foreach ($i in 1..20000) { $r.Add($i) } }
"Tableau += : {0:N0} ms" -f $a.TotalMilliseconds
"List<T>    : {0:N0} ms" -f $b.TotalMilliseconds
```

Faites tourner cet exemple : l'écart vous convaincra définitivement.

---

## 18. Sécurité et bonnes pratiques

### Ne jamais stocker de mot de passe en clair

```powershell
# MAUVAIS
$mdp = "MonMotDePasse123"

# BON : authentification Windows intégrée (aucun secret à gérer)
"Server=$srv;Database=$db;Integrated Security=True;"

# Si un secret est vraiment nécessaire : chiffré par DPAPI,
# déchiffrable uniquement par VOTRE compte sur CETTE machine
$secure = Read-Host "Mot de passe" -AsSecureString
$secure | ConvertFrom-SecureString | Set-Content "$env:APPDATA\cred.txt"

$secure = Get-Content "$env:APPDATA\cred.txt" | ConvertTo-SecureString
$cred   = New-Object System.Management.Automation.PSCredential('user', $secure)
```

### Toujours utiliser -LiteralPath

```powershell
Get-Content -Path "C:\data\rapport[2024].csv"          # ÉCHOUE : [ ] = joker
Get-Content -LiteralPath "C:\data\rapport[2024].csv"   # OK
```

Les crochets, accolades et backticks sont fréquents dans les noms de fichiers métier.

### Valider les entrées, journaliser les sorties

```powershell
[ValidateScript({ Test-Path $_ -PathType Leaf })]
[string]$FichierSource
```

### Ne jamais écraser sans sauvegarde

```powershell
if (Test-Path $sortie) {
    Copy-Item $sortie "$sortie.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}
```

### Idempotence

Un bon script ETL peut être **relancé sans dégât**. Testez : lancez-le deux fois de suite.
Si le second passage duplique des lignes ou échoue, la conception est à revoir.

### Journalisation

Tout traitement non supervisé doit écrire un log horodaté : sans lui, un échec nocturne est
indébogable. Voir `Write-Log` dans la bibliothèque fournie.

---

## 19. Déboguer efficacement

```powershell
# Points d'arrêt
Set-PSBreakpoint -Script .\script.ps1 -Line 42
Set-PSBreakpoint -Variable compteur -Mode Write     # arrêt à chaque modification

# Mode pas-à-pas dans la console
# (dans le débogueur : s = step into, v = step over, c = continue, q = quit)

# Trace détaillée
Set-PSDebug -Trace 1        # affiche chaque ligne exécutée
Set-PSDebug -Off

# Inspecter un objet inconnu
$obj | Get-Member
$obj | Format-List *
$obj | ConvertTo-Json -Depth 3
```

### Bloc de diagnostic à copier dans vos scripts

Utile quand le débogage se fait à distance (log, capture d'écran) :

```powershell
try {
    # ... votre code ...
}
catch {
    Write-Host "===== ERREUR =====" -ForegroundColor Red
    Write-Host ("Message     : {0}" -f $_.Exception.Message)
    Write-Host ("Ligne       : {0}" -f $_.InvocationInfo.ScriptLineNumber)
    Write-Host ("Instruction : {0}" -f $_.InvocationInfo.Line.Trim())
    Write-Host ("Type .NET   : {0}" -f $_.Exception.GetType().FullName)
    Write-Host $_.ScriptStackTrace
    throw
}
```

---

## 20. Pièges connus de PowerShell 5.1

Liste issue de l'expérience terrain — chacun de ces points a déjà coûté des heures de débogage.

| Piège | Symptôme | Solution |
|---|---|---|
| `+` polymorphe | `op_Addition` introuvable | Utiliser `-f` pour formater |
| Indexeur 2D `$a[$i,$j] =` | `op_Addition`, comportement erratique | `.SetValue(v,i,j)` / `.GetValue(i,j)` |
| Sortie implicite | La fonction renvoie des valeurs parasites | `[void]` devant les appels de méthode |
| `+=` sur tableau | Script très lent | `List[T]` |
| BOM UTF-8 | `Primitive JSON non valide`, import SQL cassé | `[IO.File]::ReadAllText()` |
| `-Encoding UTF8` en écriture | Ajoute un BOM | `UTF8Encoding::new($false)` |
| `Import-Csv` typage | `1+1 = "11"` | Caster explicitement |
| `ConvertTo-Json -Depth` | Objets tronqués | `-Depth 10` |
| `$x -eq $null` | Faux positif sur tableau | `$null -eq $x` |
| COM non libéré | `EXCEL.EXE` fantôme | `finally` + `ReleaseComObject` |
| `try/catch` inefficace | L'erreur passe au travers | `-ErrorAction Stop` |
| Appel avec parenthèses | Paramètres mal transmis | `Ma-Fonction -A 1 -B 2` |
| Backtick de continuation | Erreur de parsing si espace après | Éviter, ou parenthèses englobantes |
| Classe modifiée non prise en compte | Ancien comportement persistant | Relancer la session PowerShell |
| `-Path` avec `[ ]` | Fichier non trouvé | `-LiteralPath` |

---

## Pour aller plus loin

Une fois ces bases acquises, la bibliothèque `PSToolkit.psm1` fournie avec cette formation
met en pratique tous ces principes : chaque fonction est commentée, validée, et conçue pour
fonctionner sans droits administrateur.

Ordre d'apprentissage suggéré :

1. Chapitres 1 à 7 — les bases, à maîtriser absolument
2. Chapitres 8 à 10 — écrire des fonctions propres
3. Chapitre 13 à 15 — vos cas d'usage quotidiens ETL
4. Chapitre 17 — quand vos scripts deviennent lents
5. Chapitre 11 — quand vos scripts deviennent gros
