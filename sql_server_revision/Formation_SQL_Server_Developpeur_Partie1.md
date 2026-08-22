# Formation complète — Développeur SQL Server Senior

**Objectif** : passer d'un niveau rouillé à un niveau développeur SQL Server confirmé, capable d'écrire des procédures stockées optimisées, de croiser plusieurs tables intelligemment, de comprendre les index et les plans d'exécution, et de tenir une conversation technique sur le partitionnement et le stockage sans être pris au dépourvu.

**Méthode** : chaque chapitre suit la structure — concept → pourquoi ça existe → syntaxe → exemple concret → piège classique → exercice avec corrigé. Ne saute pas les exercices, c'est là que la matière se fixe.

**Base de travail** : tous les exemples utilisent le schéma **SEEDVIE** de ton labo (Clients, Contrats, DimClient, DimProduit, FactMouvements...). Si tu l'as toujours en local, exécute les requêtes au fur et à mesure. Sinon, les exemples restent lisibles en autonomie.

---

## Table des matières

**Partie 1 — Fondations solides**
1. Rappel des bases (SELECT, WHERE, tri, types)
2. Les jointures en profondeur
3. Agrégations, GROUP BY et HAVING

**Partie 2 — Manipuler des données complexes**
4. Sous-requêtes, CTE, tables temporaires, variables table
5. Fonctions de fenêtrage (Window Functions)
6. Pivots et requêtes de croisement

**Partie 3 — Programmation T-SQL**
7. Procédures stockées avancées
8. Fonctions (scalaires, table, inline)
9. Boucles, curseurs, et pourquoi les éviter

**Partie 4 — Performance et moteur interne**
10. Index — le guide complet
11. Lire un plan d'exécution
12. Statistiques et paramètre sniffing

**Partie 5 — Stockage et architecture physique**
13. Fichiers, filegroups et tempdb
14. Le partitionnement — le sujet qui t'a bloqué
15. Verrouillage et niveaux d'isolation approfondis

**Partie 6 — Mise en pratique**
16. Méthodologie pour écrire une bonne requête
17. Exercices de synthèse avec corrigés complets
18. Cheat sheet finale

---

# PARTIE 1 — FONDATIONS SOLIDES

## Chapitre 1 — Rappel des bases

### L'ordre d'écriture vs l'ordre d'exécution — le concept fondateur

C'est **LE** point que tout développeur SQL doit avoir en tête en permanence, et c'est souvent mal enseigné. Tu **écris** une requête dans un ordre, mais SQL Server l'**exécute** dans un ordre complètement différent :

```
ORDRE D'ÉCRITURE           ORDRE D'EXÉCUTION RÉEL
─────────────────          ───────────────────────
SELECT                     1. FROM
FROM                       2. WHERE
WHERE                      3. GROUP BY
GROUP BY                   4. HAVING
HAVING                     5. SELECT (+ alias créés ici)
ORDER BY                   6. ORDER BY
```

**Pourquoi c'est crucial à savoir** : ça explique des comportements qui semblent bizarres au débutant. Par exemple :

```sql
-- Ceci PLANTE
SELECT Montant * 2 AS DoubleMontant
FROM FactMouvements
WHERE DoubleMontant > 1000;   -- ❌ Erreur : DoubleMontant inconnu ici
```

**Pourquoi ça plante** : le `WHERE` s'exécute (étape 2) **avant** le `SELECT` (étape 5). L'alias `DoubleMontant` n'existe pas encore au moment où `WHERE` s'exécute — il est créé plus tard.

```sql
-- Version correcte
SELECT Montant * 2 AS DoubleMontant
FROM FactMouvements
WHERE Montant * 2 > 1000;    -- ✅ on répète l'expression
```

À l'inverse, `ORDER BY` s'exécute **en dernier**, donc lui peut utiliser les alias du `SELECT` sans problème :
```sql
SELECT Montant * 2 AS DoubleMontant
FROM FactMouvements
ORDER BY DoubleMontant;      -- ✅ OK, ORDER BY est après SELECT
```

**Retiens cette règle** : chaque fois qu'une requête te surprend, demande-toi « à quelle étape de l'exécution réelle suis-je, et qu'est-ce qui existe déjà à ce moment-là ? »

### Les types de données — ce qu'il faut vraiment savoir

| Catégorie | Types | Piège à connaître |
|---|---|---|
| Entiers | `TINYINT`, `SMALLINT`, `INT`, `BIGINT` | Choisis le plus petit qui couvre ton besoin — impacte la taille des index |
| Décimaux exacts | `DECIMAL(p,s)`, `NUMERIC(p,s)` | **Toujours pour l'argent** — jamais FLOAT |
| Décimaux approximatifs | `FLOAT`, `REAL` | Erreurs d'arrondi binaire — jamais pour du financier |
| Texte | `VARCHAR(n)`, `NVARCHAR(n)` | `N` = Unicode (accents, autres langues), coûte 2x plus de stockage |
| Texte long | `VARCHAR(MAX)`, `NVARCHAR(MAX)` | Stocké différemment en interne, évite si tu peux borner la taille |
| Date/heure | `DATE`, `DATETIME2`, `DATETIMEOFFSET` | Préfère `DATETIME2` à `DATETIME` (plus précis, mieux normé) |
| Booléen | `BIT` | 0/1/NULL, pas de vrai booléen en SQL Server |
| Identifiant unique | `UNIQUEIDENTIFIER` | Un GUID — attention, fragmente les index si mal utilisé en clé de tri |

**Piège classique n°1** : comparer des types différents entraîne une **conversion implicite** qui peut être coûteuse ou dangereuse.
```sql
-- Si NumeroContrat est VARCHAR et que tu compares à un entier
WHERE NumeroContrat = 12345   -- SQL Server convertit implicitement, parfois mal, parfois lentement
```
**Bon réflexe** : compare toujours des types identiques, convertis explicitement si besoin (`CAST`/`TRY_CAST`, vus dans nos échanges précédents).

### NULL — le concept le plus mal compris de SQL

`NULL` ne veut **pas dire zéro, ni chaîne vide** — ça veut dire « valeur inconnue/absente ». Ça a des conséquences logiques déroutantes :

```sql
SELECT * FROM Contrats WHERE Statut = NULL;      -- ❌ Ne renvoie JAMAIS rien, même si Statut est NULL
SELECT * FROM Contrats WHERE Statut IS NULL;     -- ✅ La bonne syntaxe
```

**Pourquoi `= NULL` ne marche jamais** : en logique à trois valeurs de SQL (`TRUE`/`FALSE`/`UNKNOWN`), comparer quelque chose à une valeur inconnue donne toujours `UNKNOWN`, jamais `TRUE`. D'où l'existence de `IS NULL` / `IS NOT NULL`, des opérateurs spéciaux dédiés.

**Piège avec les agrégats** : `NULL` est **ignoré** par `SUM`, `AVG`, `COUNT(colonne)`, mais **pas** par `COUNT(*)`.
```sql
SELECT COUNT(*) FROM Contrats;              -- compte TOUTES les lignes
SELECT COUNT(CodeProduit) FROM Contrats;    -- compte seulement les lignes où CodeProduit N'EST PAS NULL
```

**`COALESCE` et `ISNULL`** — remplacer un NULL par une valeur par défaut :
```sql
SELECT COALESCE(CodeProduit, 'INCONNU') FROM Contrats;
```
**Différence entre les deux** : `ISNULL` est propriétaire SQL Server, prend exactement 2 arguments, un peu plus rapide. `COALESCE` est standard ANSI (portable vers PostgreSQL, Oracle...), accepte un nombre illimité d'arguments et renvoie le premier non-NULL. **Recommandation pro** : utilise `COALESCE` par défaut — plus flexible, plus portable, différence de perf négligeable dans 99% des cas.

### Exercice 1.1

Sans exécuter, dis pourquoi cette requête plante :
```sql
SELECT ClientId, COUNT(*) AS NbContrats
FROM Contrats
WHERE NbContrats > 1
GROUP BY ClientId;
```

<details>
<summary>Corrigé</summary>

Même erreur que l'exemple du début de chapitre : `WHERE` s'exécute **avant** `GROUP BY` et `SELECT`, donc l'alias `NbContrats` n'existe pas encore. Pour filtrer sur un résultat d'agrégat, il faut utiliser `HAVING` (vu au chapitre 3), qui s'exécute **après** `GROUP BY` :
```sql
SELECT ClientId, COUNT(*) AS NbContrats
FROM Contrats
GROUP BY ClientId
HAVING COUNT(*) > 1;
```
</details>

---

## Chapitre 2 — Les jointures en profondeur

### Pourquoi les jointures sont LE cœur du métier

Ta mission consiste à « croiser plusieurs tables pour rechercher des informations précises ». C'est exactement le rôle des jointures — combiner des lignes de plusieurs tables selon une condition de correspondance.

### INNER JOIN — l'intersection

```sql
SELECT c.NumeroContrat, cl.Nom, cl.Prenom
FROM Contrats c
INNER JOIN Clients cl ON cl.ClientId = c.ClientId;
```
**Ne renvoie que** les lignes qui trouvent une correspondance **des deux côtés**. Si un contrat référence un `ClientId` qui n'existe plus dans `Clients`, ce contrat **disparaît silencieusement** du résultat.

### LEFT JOIN (ou LEFT OUTER JOIN) — tout de gauche + correspondances

```sql
SELECT c.NumeroContrat, cl.Nom
FROM Contrats c
LEFT JOIN Clients cl ON cl.ClientId = c.ClientId;
```
**Garde toutes les lignes de la table de gauche** (`Contrats`), même si aucune correspondance n'est trouvée à droite — dans ce cas, les colonnes de droite (`cl.Nom`) valent `NULL`.

**C'est LE pattern qu'on a utilisé ensemble pour détecter les rejets** dans ton labo : `LEFT JOIN` + test `IS NULL` sur la table de droite = « trouve-moi tout ce qui n'a **pas** de correspondance ».

```sql
-- Trouver les contrats orphelins (client supprimé/inexistant)
SELECT c.NumeroContrat
FROM Contrats c
LEFT JOIN Clients cl ON cl.ClientId = c.ClientId
WHERE cl.ClientId IS NULL;
```

### RIGHT JOIN — le symétrique, rarement utilisé

```sql
SELECT c.NumeroContrat, cl.Nom
FROM Contrats c
RIGHT JOIN Clients cl ON cl.ClientId = c.ClientId;
```
Garde toutes les lignes de la table de **droite**. **En pratique, `RIGHT JOIN` est rarement utilisé** — la convention pro est de toujours réécrire en `LEFT JOIN` en inversant l'ordre des tables, pour la lisibilité et la cohérence d'équipe :
```sql
-- Équivalent, mais plus lisible en convention d'équipe
SELECT c.NumeroContrat, cl.Nom
FROM Clients cl
LEFT JOIN Contrats c ON c.ClientId = cl.ClientId;
```

### FULL JOIN (FULL OUTER JOIN) — l'union complète

```sql
SELECT c.NumeroContrat, cl.Nom
FROM Contrats c
FULL JOIN Clients cl ON cl.ClientId = c.ClientId;
```
Garde **toutes** les lignes des deux côtés, avec des `NULL` là où il n'y a pas de correspondance. Utile pour des **rapprochements bidirectionnels** — typiquement, comparer deux extractions pour trouver ce qui manque de chaque côté (rappelle-toi l'exemple `HashSet.Except()` de ton labo, en SQL pur c'est le `FULL JOIN` + `IS NULL` des deux côtés qui fait ça).

```sql
-- Rapprochement source vs cible après migration : qui manque où ?
SELECT
    COALESCE(s.NumeroContrat, t.NumeroContrat) AS NumeroContrat,
    CASE
        WHEN t.NumeroContrat IS NULL THEN 'Manquant en CIBLE'
        WHEN s.NumeroContrat IS NULL THEN 'Manquant en SOURCE'
    END AS Anomalie
FROM Source s
FULL JOIN Cible t ON t.NumeroContrat = s.NumeroContrat
WHERE s.NumeroContrat IS NULL OR t.NumeroContrat IS NULL;
```

### CROSS JOIN — le produit cartésien (attention danger)

```sql
SELECT p.LibelleProduit, d.Annee
FROM DimProduit p
CROSS JOIN DimDate d;
```
Combine **chaque ligne de A avec chaque ligne de B**, sans condition. Si `DimProduit` a 5 lignes et `DimDate` a 8000 lignes, le résultat a **40 000 lignes**. **Rarement voulu par accident** — mais volontairement utile pour générer des combinaisons (ex : générer toutes les combinaisons produit × mois pour un rapport qui doit afficher des zéros là où il n'y a pas de données, plutôt que des trous).

**⚠️ Piège n°1 des débutants** : oublier la condition `ON` dans un JOIN classique **transforme accidentellement ta requête en CROSS JOIN** et explose le nombre de lignes (souvent avec des doublons monstrueux). Si ton résultat a soudain 50x plus de lignes que prévu, **vérifie en premier tes conditions de jointure**.

### SELF JOIN — une table jointe à elle-même

```sql
-- Trouver les clients qui partagent la même ville (pour un contrôle qualité)
SELECT c1.Nom AS Client1, c2.Nom AS Client2, c1.Ville
FROM Clients c1
JOIN Clients c2 ON c1.Ville = c2.Ville AND c1.ClientId < c2.ClientId;
```
**Pourquoi `c1.ClientId < c2.ClientId`** : sans cette condition, tu obtiendrais chaque paire **deux fois** (A-B et B-A), plus chaque client apparié avec lui-même. Le `<` élimine les doublons et l'auto-appariement en une seule condition — un réflexe à connaître.

**Cas d'usage typique en assurance vie** : trouver des contrats liés hiérarchiquement (un contrat "parent" et ses avenants), des employés et leur manager, des comparaisons de versions successives d'une même donnée (SCD2 — comparer la version N et N-1 d'un client).

### Jointures multiples — l'ordre compte-t-il ?

```sql
SELECT f.Montant, dc.NomComplet, dp.LibelleProduit, dd.Annee
FROM FactMouvements f
JOIN DimClient  dc ON dc.ClientKey  = f.ClientKey
JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
JOIN DimDate    dd ON dd.DateKey    = f.DateKey;
```
**L'ordre d'écriture n'a généralement pas d'importance fonctionnelle** — l'optimiseur SQL Server réorganise les jointures selon ce qu'il juge le plus efficace (basé sur les statistiques, la taille des tables, les index disponibles), pas selon l'ordre où tu les as écrites. **Sauf** dans de rares cas avec des hints de forçage (`OPTION (FORCE ORDER)`), que tu n'utiliseras qu'en dernier recours de tuning avancé.

### Exercice 2.1

Écris une requête qui liste tous les **clients qui n'ont jamais souscrit aucun contrat**.

<details>
<summary>Corrigé</summary>

```sql
SELECT cl.ClientId, cl.Nom, cl.Prenom
FROM Clients cl
LEFT JOIN Contrats c ON c.ClientId = cl.ClientId
WHERE c.ContratId IS NULL;
```
`LEFT JOIN` garde tous les clients ; pour ceux sans contrat, `c.ContratId` est `NULL` ; le `WHERE ... IS NULL` isole exactement ce cas.
</details>

### Exercice 2.2

Pourquoi cette requête est-elle dangereuse si on l'exécute par erreur sur de grosses tables ?
```sql
SELECT * FROM Contrats, Clients;
```

<details>
<summary>Corrigé</summary>

C'est un **CROSS JOIN implicite** — la syntaxe avec virgule sans `ON` produit un produit cartésien. Si `Contrats` a 800 lignes et `Clients` 500, le résultat a **400 000 lignes**, sans aucun sens fonctionnel. C'est un oubli classique de jointure — toujours utiliser la syntaxe explicite `JOIN ... ON` pour éviter ce piège silencieux.
</details>

---

## Chapitre 3 — Agrégations, GROUP BY et HAVING

### Les fonctions d'agrégat de base

| Fonction | Rôle | Piège |
|---|---|---|
| `COUNT(*)` | Compte toutes les lignes | Inclut les NULL |
| `COUNT(colonne)` | Compte les lignes non-NULL | Exclut les NULL |
| `COUNT(DISTINCT colonne)` | Compte les valeurs distinctes | Coût de tri interne |
| `SUM(colonne)` | Somme | Ignore les NULL, renvoie NULL si tout est NULL |
| `AVG(colonne)` | Moyenne | Ignore les NULL (donc pas divisé par le vrai total de lignes !) |
| `MIN` / `MAX` | Min/Max | Fonctionne aussi sur dates et texte |
| `STRING_AGG` | Concatène en une chaîne (SQL 2017+) | Utile pour du reporting texte |

**Piège classique avec `AVG`** :
```sql
-- Si 2 des 10 lignes ont un Montant NULL,
-- AVG divise par 8 (lignes non-NULL), pas par 10 (total)
SELECT AVG(Montant) FROM FactMouvements;
```
Si tu veux vraiment diviser par le total de lignes (NULL inclus comme 0) :
```sql
SELECT SUM(Montant) / COUNT(*) FROM FactMouvements;
```

### GROUP BY — regrouper pour agréger

```sql
SELECT CodeProduit, COUNT(*) AS NbContrats, AVG(DATEDIFF(YEAR, DateSouscription, GETDATE())) AS AncienneteMoyenne
FROM Contrats
GROUP BY CodeProduit;
```

**Règle d'or absolue** : **toute colonne du SELECT qui n'est pas dans une fonction d'agrégat doit être dans le GROUP BY.** SQL Server refuse sinon :
```sql
-- ❌ Erreur : Statut n'est ni agrégé ni dans le GROUP BY
SELECT CodeProduit, Statut, COUNT(*)
FROM Contrats
GROUP BY CodeProduit;
```
```sql
-- ✅ Correct
SELECT CodeProduit, Statut, COUNT(*)
FROM Contrats
GROUP BY CodeProduit, Statut;
```

**Pourquoi cette règle existe** : conceptuellement, `GROUP BY CodeProduit` réduit chaque groupe de produit à **une seule ligne**. Si `Statut` peut varier à l'intérieur d'un même groupe de produit (plusieurs statuts différents pour le même produit), SQL Server ne sait pas laquelle des valeurs de `Statut` afficher — d'où l'obligation de soit l'agréger, soit l'ajouter au regroupement.

### GROUP BY sur plusieurs colonnes — les niveaux de détail

```sql
SELECT dd.Annee, dd.Mois, dp.FamilleProduit, SUM(f.Montant) AS Total
FROM FactMouvements f
JOIN DimDate dd ON dd.DateKey = f.DateKey
JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
GROUP BY dd.Annee, dd.Mois, dp.FamilleProduit
ORDER BY dd.Annee, dd.Mois, dp.FamilleProduit;
```
Chaque combinaison unique (Année, Mois, Famille) devient une ligne du résultat — c'est le mécanisme même du **niveau de détail** en reporting/BI, exactement ce que QlikSense affichera dans un tableau croisé.

### HAVING — filtrer après agrégation

```sql
SELECT ClientId, COUNT(*) AS NbContrats
FROM Contrats
GROUP BY ClientId
HAVING COUNT(*) > 1;
```
**`WHERE` filtre les lignes avant regroupement, `HAVING` filtre les groupes après agrégation.** C'est la conséquence directe de l'ordre d'exécution vu au chapitre 1 (`WHERE` étape 2, `GROUP BY` étape 3, `HAVING` étape 4).

**On peut combiner les deux** :
```sql
SELECT CodeProduit, COUNT(*) AS Nb
FROM Contrats
WHERE Statut = 'Actif'         -- filtre AVANT regroupement (sur les lignes brutes)
GROUP BY CodeProduit
HAVING COUNT(*) > 50;          -- filtre APRÈS regroupement (sur les groupes)
```

### GROUPING SETS, ROLLUP, CUBE — les totaux multi-niveaux (avancé)

Pour un rapport qui doit afficher à la fois le détail **et** les sous-totaux (typiquement un besoin de reporting financier) :

```sql
SELECT dp.FamilleProduit, dd.Annee, SUM(f.Montant) AS Total
FROM FactMouvements f
JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
JOIN DimDate dd ON dd.DateKey = f.DateKey
GROUP BY ROLLUP(dp.FamilleProduit, dd.Annee);
```
`ROLLUP` ajoute automatiquement des lignes de sous-total (par famille, tous les ans confondus) et une ligne de total général (`NULL, NULL`). C'est ce que tu obtiendrais autrement avec plusieurs `UNION ALL` de requêtes différentes — `ROLLUP` le fait en une seule passe, plus efficace.

**`GROUPING(colonne)`** permet de distinguer un vrai `NULL` de donnée d'un `NULL` généré par le sous-total :
```sql
SELECT
    dp.FamilleProduit,
    dd.Annee,
    SUM(f.Montant) AS Total,
    CASE WHEN GROUPING(dd.Annee) = 1 THEN 'Sous-total Famille' ELSE 'Détail' END AS TypeLigne
FROM FactMouvements f
JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
JOIN DimDate dd ON dd.DateKey = f.DateKey
GROUP BY ROLLUP(dp.FamilleProduit, dd.Annee);
```

### Exercice 3.1

Écris une requête qui trouve les **produits dont l'encours total dépasse 500 000 €**, avec le nombre de mouvements associés.

<details>
<summary>Corrigé</summary>

```sql
SELECT dp.LibelleProduit, SUM(f.Montant) AS EncoursTotal, COUNT(*) AS NbMouvements
FROM FactMouvements f
JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
GROUP BY dp.LibelleProduit
HAVING SUM(f.Montant) > 500000
ORDER BY EncoursTotal DESC;
```
</details>

---

# PARTIE 2 — MANIPULER DES DONNÉES COMPLEXES

## Chapitre 4 — Sous-requêtes, CTE, tables temporaires, variables table

C'est un des chapitres les plus importants pour toi : **savoir choisir le bon outil selon le besoin** est exactement la compétence "développeur SQL senior" que tu demandes.

### Sous-requête scalaire — renvoie une seule valeur

```sql
SELECT NumeroContrat, Montant,
    (SELECT AVG(Montant) FROM FactMouvements) AS MoyenneGenerale
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```
Utilisable partout où une valeur unique est attendue (SELECT, WHERE, comparaison).

### Sous-requête corrélée — dépend de la ligne externe

```sql
SELECT c.NumeroContrat,
    (SELECT COUNT(*) FROM FactMouvements f WHERE f.ContratKey = dc.ContratKey) AS NbMouvements
FROM DimContrat dc;
```
**Piège de performance** : une sous-requête corrélée s'exécute potentiellement **une fois par ligne** de la requête externe — sur une grosse table, ça peut devenir très lent. **Souvent, une jointure + GROUP BY est plus performante** pour le même résultat :
```sql
-- Version généralement plus rapide, même résultat
SELECT dc.NumeroContrat, COUNT(f.MouvementKey) AS NbMouvements
FROM DimContrat dc
LEFT JOIN FactMouvements f ON f.ContratKey = dc.ContratKey
GROUP BY dc.NumeroContrat;
```

### Sous-requête avec IN / EXISTS

```sql
-- Avec IN
SELECT * FROM DimContrat WHERE ContratKey IN (SELECT ContratKey FROM FactMouvements WHERE Montant > 10000);

-- Avec EXISTS (rappel de notre échange précédent : souvent préférable)
SELECT * FROM DimContrat dc
WHERE EXISTS (SELECT 1 FROM FactMouvements f WHERE f.ContratKey = dc.ContratKey AND f.Montant > 10000);
```
**Rappel du piège NOT IN** vu ensemble : si la sous-requête contient un NULL, `NOT IN` renvoie un résultat vide de façon contre-intuitive. **Toujours préférer `NOT EXISTS`** pour les exclusions.

### CTE (Common Table Expression) — la requête nommée temporaire

```sql
;WITH ContratsActifs AS (
    SELECT * FROM DimContrat WHERE Statut = 'Actif'
)
SELECT ca.NumeroContrat, SUM(f.Montant) AS Total
FROM ContratsActifs ca
JOIN FactMouvements f ON f.ContratKey = ca.ContratKey
GROUP BY ca.NumeroContrat;
```
**Avantages** : lisibilité (nomme des étapes intermédiaires), permet la **récursivité** (voir plus bas), n'existe que pour la requête immédiatement suivante (rappel de notre échange précédent sur le SCD2 — d'où la nécessité de le réécrire si utilisé plusieurs fois).

**CTE récursive** — un outil puissant pour les hiérarchies :
```sql
-- Générer une série de dates (technique vue dans ton labo, DimDate)
;WITH Dates AS (
    SELECT CAST('2026-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Dates WHERE d < '2026-12-31'
)
SELECT * FROM Dates
OPTION (MAXRECURSION 0);   -- 0 = pas de limite (par défaut limité à 100 niveaux)
```
**Cas d'usage classique en entreprise** : hiérarchies organisationnelles (manager → subordonnés), arborescences de catégories produits, calendriers.

### Table temporaire (`#temp`) — pour des résultats intermédiaires volumineux

```sql
SELECT dc.ContratKey, dc.NumeroContrat, dc.CodeProduit
INTO #ContratsActifs
FROM DimContrat dc
WHERE dc.Statut = 'Actif';

CREATE INDEX IX_temp_ProduitKey ON #ContratsActifs(CodeProduit);   -- on peut même indexer !

SELECT ca.CodeProduit, SUM(f.Montant)
FROM #ContratsActifs ca
JOIN FactMouvements f ON f.ContratKey = ca.ContratKey
GROUP BY ca.CodeProduit;

DROP TABLE #ContratsActifs;   -- bonne pratique : nettoyer explicitement
```
**Pourquoi utiliser une table temporaire plutôt qu'un CTE** :
- Le résultat est **matérialisé** (calculé et stocké une fois) plutôt que réévalué.
- On peut **l'indexer** pour accélérer les jointures suivantes.
- On peut la **réutiliser plusieurs fois** dans le même batch, sans redéclaration (contrairement au CTE).
- Utile quand le jeu de données intermédiaire est **gros** ou **réutilisé plusieurs fois**.

**`#temp` (locale) vs `##temp` (globale)** : `#` n'est visible que dans ta session courante. `##` (double dièse) est visible par **toutes** les sessions connectées — rarement utilisé, et risqué en environnement multi-utilisateur (conflits de nom).

### Variable table (`@table`) — pour de petits volumes

```sql
DECLARE @ContratsSuspects TABLE (
    ContratKey INT,
    Montant DECIMAL(19,4)
);

INSERT INTO @ContratsSuspects
SELECT ContratKey, Montant FROM FactMouvements WHERE Montant > 10000;

SELECT * FROM @ContratsSuspects;
```
**Différences avec `#temp`** :
- Portée limitée au **batch/procédure courante** (encore plus restreint que `#temp`).
- **Pas de statistiques** tenues à jour par SQL Server dessus — l'optimiseur "devine" souvent mal la taille, ce qui peut donner de mauvais plans d'exécution sur de gros volumes.
- Généralement **plus rapide pour de petits volumes** (quelques centaines de lignes) grâce à moins d'overhead de gestion transactionnelle.

**Règle de choix pratique (résumé)** :

| Besoin | Choix |
|---|---|
| Requête simple, utilisée une seule fois | CTE |
| Récursivité (hiérarchies) | CTE récursive |
| Gros volume, réutilisé plusieurs fois, besoin d'indexer | Table temporaire `#temp` |
| Petit volume (< quelques milliers de lignes), logique procédurale | Variable table `@table` |
| Partagé entre plusieurs sessions (rare) | `##temp` globale |

### Exercice 4.1

Réécris cette sous-requête corrélée (potentiellement lente) en utilisant une jointure :
```sql
SELECT cl.Nom,
    (SELECT SUM(f.Montant) FROM FactMouvements f
     JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
     WHERE dc.ClientId = cl.ClientId) AS TotalMouvements
FROM Clients cl;
```

<details>
<summary>Corrigé</summary>

```sql
SELECT cl.Nom, SUM(f.Montant) AS TotalMouvements
FROM Clients cl
LEFT JOIN DimContrat dc ON dc.ClientId = cl.ClientId
LEFT JOIN FactMouvements f ON f.ContratKey = dc.ContratKey
GROUP BY cl.Nom;
```
`LEFT JOIN` (et non `JOIN`) pour garder les clients sans mouvement (ils auront `NULL`/0 via `SUM` qui ignore les NULL). Cette version évite la ré-exécution de la sous-requête pour chaque client.
</details>

---

## Chapitre 5 — Fonctions de fenêtrage (Window Functions)

**C'est l'un des outils les plus puissants et les moins maîtrisés par les développeurs SQL de niveau intermédiaire.** Si tu maîtrises ce chapitre, tu te distingues clairement.

### Le concept

Une fonction de fenêtrage calcule une valeur **en tenant compte d'un groupe de lignes liées ("la fenêtre")**, **sans réduire le nombre de lignes du résultat** — contrairement à `GROUP BY` qui, lui, condense les lignes.

```sql
SELECT
    NumeroContrat,
    Montant,
    AVG(Montant) OVER () AS MoyenneGenerale   -- même valeur répétée sur CHAQUE ligne
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```
Contrairement à `GROUP BY` qui donnerait une seule ligne de résultat, ici **toutes les lignes originales sont conservées**, chacune avec la moyenne générale affichée à côté. C'est la différence fondamentale à bien intégrer.

### PARTITION BY — fenêtrer par groupe

```sql
SELECT
    NumeroContrat,
    CodeProduit,
    Montant,
    AVG(Montant) OVER (PARTITION BY CodeProduit) AS MoyenneParProduit
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```
Ici, la moyenne est calculée **par groupe de CodeProduit**, mais chaque ligne individuelle reste visible avec son détail — impossible d'obtenir ça avec un simple `GROUP BY` sans perdre le détail ligne à ligne.

### ROW_NUMBER, RANK, DENSE_RANK — numéroter et classer

```sql
SELECT
    NumeroContrat,
    Montant,
    ROW_NUMBER() OVER (ORDER BY Montant DESC) AS Rang
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```

**Différences essentielles entre les trois** (cas avec ex-aequo) :

| Montant | ROW_NUMBER | RANK | DENSE_RANK |
|---|---|---|---|
| 1000 | 1 | 1 | 1 |
| 1000 | 2 | 1 | 1 |
| 900 | 3 | 3 | 2 |
| 800 | 4 | 4 | 3 |

- **`ROW_NUMBER`** : toujours unique, jamais d'ex-aequo (départage arbitrairement selon l'ordre).
- **`RANK`** : les ex-aequo partagent le même rang, mais **saute** des numéros après (1, 1, 3...).
- **`DENSE_RANK`** : les ex-aequo partagent le même rang, **sans sauter** de numéros (1, 1, 2...).

**Le pattern "top-1 par groupe"** — l'usage le plus fréquent en entreprise, qu'on a déjà vu ensemble dans ton labo :
```sql
;WITH Classement AS (
    SELECT
        NumeroContrat, Montant, DateOperation,
        ROW_NUMBER() OVER (PARTITION BY ContratKey ORDER BY DateOperation DESC) AS rn
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
)
SELECT * FROM Classement WHERE rn = 1;   -- le dernier mouvement par contrat
```

### Fonctions de calcul cumulé — running totals

```sql
SELECT
    NumeroContrat,
    DateOperation,
    MontantSigne,
    SUM(MontantSigne) OVER (
        PARTITION BY ContratKey
        ORDER BY DateOperation
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS EncoursCumule
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```
**Décryptage de `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`** : « prends toutes les lignes depuis le début de la partition jusqu'à la ligne courante » — c'est exactement ça qui donne le cumul progressif (running total). C'est le calcul qu'on avait fait ensemble dans ton labo pour l'encours cumulé.

**Autres bornes de fenêtre courantes** :
- `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` — moyenne mobile sur 3 lignes (les 2 précédentes + la courante).
- `ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING` — cumul inversé (du présent vers la fin).

### LAG et LEAD — accéder à la ligne précédente/suivante

```sql
SELECT
    NumeroContrat,
    DateOperation,
    Montant,
    LAG(Montant) OVER (PARTITION BY ContratKey ORDER BY DateOperation) AS MontantPrecedent,
    Montant - LAG(Montant) OVER (PARTITION BY ContratKey ORDER BY DateOperation) AS Variation
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey;
```
**`LAG`** regarde la ligne précédente, **`LEAD`** regarde la ligne suivante — sans avoir besoin d'un self-join. **Cas d'usage classique** : calculer une variation entre deux mouvements successifs, détecter un changement de statut, comparer une valeur à celle du mois précédent.

### Exercice 5.1

Écris une requête qui affiche, pour chaque produit, les **3 mouvements les plus importants en montant**.

<details>
<summary>Corrigé</summary>

```sql
;WITH Classement AS (
    SELECT
        dp.LibelleProduit,
        f.Montant,
        dc.NumeroContrat,
        ROW_NUMBER() OVER (PARTITION BY dp.ProduitKey ORDER BY f.Montant DESC) AS rn
    FROM FactMouvements f
    JOIN DimProduit dp ON dp.ProduitKey = f.ProduitKey
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
)
SELECT LibelleProduit, NumeroContrat, Montant
FROM Classement
WHERE rn <= 3
ORDER BY LibelleProduit, Montant DESC;
```
</details>

---

## Chapitre 6 — Pivots et requêtes de croisement

### PIVOT — transformer des lignes en colonnes

```sql
SELECT NumeroContrat, [VERSEMENT], [RACHAT_PARTIEL], [ARBITRAGE]
FROM (
    SELECT dc.NumeroContrat, f.TypeOperation, f.Montant
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
) AS Source
PIVOT (
    SUM(Montant) FOR TypeOperation IN ([VERSEMENT], [RACHAT_PARTIEL], [ARBITRAGE])
) AS Pivoted;
```
**Décryptage** : chaque valeur distincte de `TypeOperation` devient une **colonne** du résultat, avec `SUM(Montant)` comme valeur agrégée dans chaque cellule. C'est exactement le type de tableau croisé qu'on affiche souvent en reporting Excel/QlikSense — sauf qu'ici on le génère directement en SQL.

**Limitation à connaître** : le `PIVOT` T-SQL exige de **lister explicitement** les valeurs à transformer en colonnes (`[VERSEMENT], [RACHAT_PARTIEL]...`). Si les types d'opération changent dynamiquement, il faut du **SQL dynamique** (`sp_executesql`) pour générer la liste automatiquement — plus complexe, à réserver aux cas où c'est vraiment nécessaire.

### UNPIVOT — l'opération inverse

```sql
SELECT NumeroContrat, TypeOperation, Montant
FROM TableAvecColonnesParType
UNPIVOT (
    Montant FOR TypeOperation IN ([VERSEMENT], [RACHAT_PARTIEL], [ARBITRAGE])
) AS Unpivoted;
```
Utile quand tu reçois un fichier Excel mal structuré (une colonne par mois par exemple) et que tu dois le remettre en format "normalisé" (une ligne par observation) avant de le charger dans un entrepôt — exactement le genre de situation que tu peux rencontrer avec les fichiers Access/Excel de ta mission.

### Alternative moderne : agrégation conditionnelle (souvent plus simple)

```sql
SELECT
    dc.NumeroContrat,
    SUM(CASE WHEN f.TypeOperation = 'VERSEMENT' THEN f.Montant ELSE 0 END) AS Versements,
    SUM(CASE WHEN f.TypeOperation = 'RACHAT_PARTIEL' THEN f.Montant ELSE 0 END) AS Rachats
FROM FactMouvements f
JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
GROUP BY dc.NumeroContrat;
```
**Même résultat** que le PIVOT, syntaxe `CASE WHEN` + `SUM` — beaucoup de développeurs SQL préfèrent cette forme, plus flexible et plus lisible pour qui n'a pas mémorisé la syntaxe PIVOT. **Les deux sont valides**, à toi de voir laquelle ton équipe utilise en convention.

### Exercice 6.1

En utilisant l'agrégation conditionnelle, compte le nombre de contrats **Actifs** et **Rachetés** par produit, sur une seule ligne par produit.

<details>
<summary>Corrigé</summary>

```sql
SELECT
    CodeProduit,
    SUM(CASE WHEN Statut = 'Actif' THEN 1 ELSE 0 END) AS NbActifs,
    SUM(CASE WHEN Statut = 'Racheté' THEN 1 ELSE 0 END) AS NbRachetes
FROM Contrats
GROUP BY CodeProduit;
```
</details>

---

*(La formation continue dans le document — Parties 3 à 6 couvrent les procédures stockées avancées, les fonctions, les boucles, les index, les plans d'exécution, le partitionnement et les exercices de synthèse.)*
