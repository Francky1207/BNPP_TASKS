### 1. Le principe fondateur : deux natures de fichiers

Tout part d'une distinction que j'ai adoptée dès le début et jamais rompue :

- **Les scripts `.ps1` autonomes** (`Extract-CreTableColumns`, `Resolve-CreViewAliases`, `Compare-DataFiles`, `New-TestLab`, `Test-ToutLePackage`, `Start-Toolkit`) — chacun se suffit à lui-même. On le lance, il travaille, il s'arrête. Zéro dépendance externe.
- **Les modules `.psm1`** (`PSToolkit.psm1`, `PSToolkit-Trace.psm1`) — des bibliothèques qu'on importe dans *ses propres* scripts avec `Import-Module`. Ils ne sont jamais exécutés directement.

Pourquoi cette séparation ? Parce que votre contrainte de transfert (GitHub, sans clic droit facile, sans presse-papier) rend chaque dépendance manquante coûteuse. Un script autonome ne peut pas planter par un `Import-Module` oublié — c'est exactement l'erreur que vous avez rencontrée avec `Import-ExcelSheet`. `Start-Toolkit.ps1` en particulier n'importe **jamais** `PSToolkit.psm1` : ses actions de menu (recherche, profilage, doublons, filtrage, fusion) sont réimplémentées en ligne, en miniature, pour que l'interface reste utilisable même si vous n'avez transféré que ce seul fichier.

### 2. `Lancer-Toolkit.bat` — le point d'entrée

Son unique rôle : rendre le lancement accessible à quelqu'un qui ne sait pas ouvrir PowerShell. Il fait deux choses :

```
1. Unblock-File sur tous les .ps1/.psm1 du dossier
2. powershell.exe -File Start-Toolkit.ps1
```

C'est tout. Aucune logique métier. Le double-clic existe uniquement parce que vous avez demandé une interface utilisable "sans grande connaissance informatique".

### 3. `Start-Toolkit.ps1` — la couche interface

Structurée en 4 classes, chacune avec une responsabilité unique (c'est le cœur de la demande "orienté objet") :

- **`ContexteToolkit`** — l'état partagé : dossier des scripts, dossier de données, dossier de sorties, historique des commandes lancées. Rien d'autre n'a le droit de stocker un chemin en dur.
- **`Affichage`** — tout ce qui s'imprime à l'écran (cadres, couleurs, messages). Si vous voulez changer l'apparence du menu demain, vous ne touchez qu'ici.
- **`Saisie`** — toutes les questions posées à l'utilisateur, avec validation intégrée. C'est elle qui liste les feuilles et colonnes Excel au lieu de vous laisser taper un nom à la main (source d'erreur classique évitée par construction).
- **`Executeur`** — construit la ligne de commande PowerShell équivalente (pour affichage pédagogique) et lance le script demandé via l'opérateur `&`, dans le **même processus** (contrairement au harnais de test, voir plus loin).

Le menu numéroté (`Invoke-ComparerFichiers`, `Invoke-AnalyserFichier`, etc.) n'est qu'une couche de traduction : chaque fonction pose 2-3 questions via `Saisie`, puis appelle soit un script autonome (`Compare-DataFiles.ps1`), soit du code inline pour les actions qui n'ont pas de script dédié.

### 4. Les scripts de traitement métier — le modèle qui se répète

`Extract-CreTableColumns.ps1`, `Resolve-CreViewAliases.ps1`, `Compare-DataFiles.ps1` partagent tous la même charpente, affinée au fil de nos itérations :

```
param(...)
$ErrorActionPreference = 'Stop'

# Bloc 0 : fonctions de traçage locales (Write-T, Write-Etape, Show-Erreur)
# Bloc 1..N : fonctions métier
# Programme principal
try {
    Start-Etape / Close-Etape autour de chaque phase
    ...
}
catch {
    Show-Erreur   # bloc de diagnostic : étape, fonction, ligne, code fautif, type .NET, pile
    exit 1        # jamais "throw" en sortie de catch — sinon PowerShell imprime
                   # un second message natif sur stderr, ce qui a cassé le harnais
}
```

Ce patron n'est pas décoratif : chaque élément vient d'un bug réel qu'on a chassé ensemble (le `throw` final qui polluait stderr, les erreurs de cast COM, le déballage de collections).

### 5. Les modules — la boîte à outils réutilisable

`PSToolkit.psm1` (42 fonctions) est organisé en 9 sections thématiques (journalisation, encodage, fichiers texte, CSV, qualité de données, Excel, SQL Server, classement de fichiers, utilitaires). Chaque fonction suit les mêmes règles de fiabilité : `-LiteralPath` systématique, `[CmdletBinding()]` avec validation des paramètres, `-WhatIf` sur tout ce qui est destructeur.

`PSToolkit-Trace.psm1` est indépendant : il ajoute une couche de traçage (`Start-Trace`, `Invoke-Step`, `Get-ErrorReport`) pour qui écrit ses propres scripts et veut le même niveau de diagnostic que les scripts fournis, sans le réécrire à chaque fois.

### 6. `New-TestLab.ps1` — le générateur de données

Trois classes : `Journal` (journalisation à niveaux), `EcrivainTexte` (écriture avec contrôle explicite du BOM — devenu critique après le bug d'encodage ANSI), `ConstructeurExcel` (construction de classeurs multi-feuilles, écriture cellule par cellule pour éviter les erreurs de marshaling COM). Il génère délibérément des données imparfaites (doublons, JSON invalide, encodage ANSI) : l'objectif n'est pas de prouver que tout marche, mais de vérifier que les erreurs sont **détectées et signalées proprement** plutôt que silencieusement ignorées.

### 7. `Test-ToutLePackage.ps1` — le harnais d'orchestration

Deux classes : `ResultatTest` (structure de résultat) et `MoteurTests` (moteur d'exécution). Point de conception le plus subtil du package : chaque script externe est lancé via **`Start-Process` avec redirection sur fichiers temporaires**, jamais via `&` avec `2>&1`. Ce n'est pas un choix arbitraire — c'est la leçon du bug qu'on a chassé ensemble : `2>&1` sur l'opérateur d'appel convertit le flux d'erreur natif en exception PowerShell terminante dès que `$ErrorActionPreference = 'Stop'` est actif, ce qui aurait coupé la capture avant même de lire le code de sortie. `Start-Process` redirige au niveau du système d'exploitation, insensible à ce mécanisme.

### 8. Les invariants transversaux, valables partout

Ce sont les règles qui ne sont écrites nulle part de façon centralisée mais qui gouvernent chaque ligne de COM Excel ou de manipulation de collection dans le package :

| Règle | Pourquoi |
|---|---|
| Lecture Excel via `UsedRange.Value2` en un seul appel | ~100× plus rapide qu'une lecture cellule par cellule |
| `.GetValue()`/`.SetValue()` plutôt que `$tab[$r,$c]` | Syntaxe ambiguë selon les versions, source de `op_Addition` |
| Cast `[string]` systématique en écriture Excel | L'adaptateur COM fige le type au premier appel |
| `return ,$X` pour protéger une collection en sortie de fonction | Sinon une liste vide ou à un élément est déballée silencieusement |
| ...et l'appelant ne doit **jamais** ré-envelopper avec `@(...)` | Double protection = corruption silencieuse (le bug le plus coûteux qu'on ait chassé) |
| `exit 1` plutôt que `throw` en sortie de bloc catch | Évite un second message d'erreur natif sur stderr |
| Aucun accent littéral dans le code source d'un `.ps1` sans BOM | PowerShell 5.1 lit un `.ps1` sans BOM en ANSI système, pas en UTF-8 |

Si vous deviez écrire un nouveau script demain, ce tableau est votre check-list de relecture avant livraison — c'est très exactement celle que j'applique maintenant grâce à la mémoire que vous m'avez demandé de garder.