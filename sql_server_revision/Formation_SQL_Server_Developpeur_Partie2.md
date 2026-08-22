# Formation SQL Server — Partie 2 : Programmation T-SQL et Performance

*(Suite directe de la Partie 1 — Chapitres 7 à 12)*

---

# PARTIE 3 — PROGRAMMATION T-SQL

## Chapitre 7 — Procédures stockées avancées

### Rappel de la structure de base (déjà vue ensemble)

```sql
CREATE OR ALTER PROCEDURE dbo.usp_MaProcedure
    @Parametre1 INT,
    @Parametre2 VARCHAR(50) = 'Défaut'   -- valeur par défaut si non fourni
AS
BEGIN
    SET NOCOUNT ON;
    -- logique
END
```

### Paramètres OUTPUT — renvoyer une valeur au code appelant

```sql
CREATE OR ALTER PROCEDURE dbo.usp_CalculerEncours
    @ContratId INT,
    @Encours DECIMAL(19,4) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Encours = COALESCE(SUM(MontantSigne), 0)
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
    WHERE dc.ContratId = @ContratId;
END
```
**Appel** :
```sql
DECLARE @Resultat DECIMAL(19,4);
EXEC dbo.usp_CalculerEncours @ContratId = 42, @Encours = @Resultat OUTPUT;
SELECT @Resultat;
```
**Quand utiliser OUTPUT plutôt qu'un simple SELECT en sortie** : quand tu as besoin d'une **valeur unique récupérable en variable** pour l'utiliser dans une logique de code appelant (autre procédure, ou C# via `SqlParameter` avec `Direction = Output`) — plutôt qu'un jeu de résultat tabulaire à consommer côté client.

### Valeur de retour (`RETURN`) — pour un code de statut simple

```sql
CREATE OR ALTER PROCEDURE dbo.usp_ValiderContrat
    @ContratId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DimContrat WHERE ContratId = @ContratId)
        RETURN -1;   -- code d'erreur : contrat introuvable

    -- logique de validation...
    RETURN 0;   -- succès
END
```
**`RETURN` n'accepte qu'un entier** (contrairement à `OUTPUT` qui accepte n'importe quel type) — utilisé traditionnellement pour des codes de statut simples (0 = succès, négatif = erreur), une convention héritée des langages procéduraux plus anciens. **En pratique moderne**, on préfère souvent gérer les erreurs via `TRY/CATCH` + `THROW` (vu ensemble sur `usp_ChargerFactMouvements`) plutôt que des codes retour numériques à interpréter.

### Gestion d'erreurs approfondie — TRY/CATCH et fonctions d'erreur

Rappel des fonctions disponibles **à l'intérieur d'un bloc CATCH** :

| Fonction | Renvoie |
|---|---|
| `ERROR_MESSAGE()` | Le texte du message d'erreur |
| `ERROR_NUMBER()` | Le numéro d'erreur SQL Server |
| `ERROR_SEVERITY()` | Le niveau de gravité |
| `ERROR_STATE()` | L'état de l'erreur |
| `ERROR_LINE()` | La ligne où l'erreur s'est produite |
| `ERROR_PROCEDURE()` | Le nom de la procédure où l'erreur est survenue |

```sql
BEGIN CATCH
    DECLARE @MsgErreur NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @NumErreur INT = ERROR_NUMBER();
    DECLARE @Ligne INT = ERROR_LINE();

    INSERT INTO dbo.RunLog (Etape, Statut, MessageErreur)
    VALUES ('MaProcedure',
            'KO',
            CONCAT('Erreur ', @NumErreur, ' ligne ', @Ligne, ' : ', @MsgErreur));

    THROW;
END CATCH
```

### RAISERROR et THROW — lever ses propres erreurs métier

```sql
-- Ancienne syntaxe (encore très présente en entreprise legacy)
IF @Montant <= 0
    RAISERROR('Le montant doit être positif', 16, 1);

-- Syntaxe moderne (SQL Server 2012+), à privilégier
IF @Montant <= 0
    THROW 50001, 'Le montant doit être positif', 1;
```
**Différences clés** :
- `THROW` respecte mieux le comportement transactionnel (arrête immédiatement l'exécution, remonte proprement dans un TRY/CATCH englobant).
- `RAISERROR` permet du formatage `printf`-style (`RAISERROR('Contrat %s invalide', 16, 1, @NumeroContrat)`), ce que `THROW` ne fait pas nativement.
- **En code neuf, préfère `THROW`** — c'est la recommandation Microsoft actuelle. Tu croiseras probablement `RAISERROR` dans du code plus ancien en mission (ta phase de garantie post-migration, justement).

### Transactions imbriquées — le piège classique

```sql
CREATE OR ALTER PROCEDURE dbo.usp_A
AS
BEGIN
    BEGIN TRANSACTION;
    -- ...
    EXEC dbo.usp_B;   -- appelle une autre procédure qui a AUSSI un BEGIN TRANSACTION
    -- ...
    COMMIT;
END
```
**Piège** : `BEGIN TRANSACTION` dans `usp_B` **n'ouvre pas une transaction indépendante** — il incrémente juste `@@TRANCOUNT`. Un `ROLLBACK` dans `usp_B` annule **toute la transaction depuis le tout début**, y compris ce que `usp_A` avait déjà fait. **Bonne pratique en entreprise** : n'ouvrir de transaction qu'au niveau "orchestrateur" le plus haut, et faire en sorte que les procédures appelées ne gèrent que leur propre `TRY/CATCH` sans `BEGIN TRANSACTION` propre, ou utiliser des **SAVEPOINT** pour un contrôle plus fin :
```sql
SAVE TRANSACTION PointDeReprise;
-- ...
ROLLBACK TRANSACTION PointDeReprise;   -- annule seulement depuis ce point, pas tout
```

### Procédures avec table en paramètre (Table-Valued Parameters — TVP)

**Le problème que ça résout** : envoyer une **liste** de valeurs à une procédure stockée, sans concaténer une chaîne de CSV bricolée.

```sql
-- 1. Définir un type de table
CREATE TYPE dbo.ListeContrats AS TABLE (ContratId INT);

-- 2. La procédure accepte ce type en paramètre
CREATE OR ALTER PROCEDURE dbo.usp_ValiderPlusieursContrats
    @Contrats dbo.ListeContrats READONLY   -- toujours READONLY, obligatoire
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dc SET Statut = 'Validé'
    FROM DimContrat dc
    JOIN @Contrats c ON c.ContratId = dc.ContratId;
END
```
**Depuis C#** (rappel de ton contexte .NET), on remplit une `DataTable` et on la passe en `SqlParameter` avec `SqlDbType.Structured` — bien plus propre et performant qu'une boucle de N appels `EXEC` individuels ou qu'une concaténation de chaîne CSV parsée côté SQL.

### Exercice 7.1

Écris une procédure `usp_ArchiverAnciensMouvements` qui déplace vers une table d'archive tous les mouvements de plus de 5 ans, avec gestion d'erreur et journalisation dans `RunLog`.

<details>
<summary>Corrigé</summary>

```sql
CREATE OR ALTER PROCEDURE dbo.usp_ArchiverAnciensMouvements
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nb INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.FactMouvements_Archive
        SELECT f.* FROM dbo.FactMouvements f
        JOIN dbo.DimDate dd ON dd.DateKey = f.DateKey
        WHERE dd.DateComplete < DATEADD(YEAR, -5, GETDATE());

        SET @nb = @@ROWCOUNT;

        DELETE f FROM dbo.FactMouvements f
        JOIN dbo.DimDate dd ON dd.DateKey = f.DateKey
        WHERE dd.DateComplete < DATEADD(YEAR, -5, GETDATE());

        COMMIT;

        INSERT INTO dbo.RunLog (Etape, Statut, NbLignes)
        VALUES ('ARCHIVE_MOUVEMENTS', 'OK', @nb);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT INTO dbo.RunLog (Etape, Statut, MessageErreur)
        VALUES ('ARCHIVE_MOUVEMENTS', 'KO', ERROR_MESSAGE());
        THROW;
    END CATCH
END
```
</details>

---

## Chapitre 8 — Fonctions (scalaires, table, inline)

### Fonction scalaire — renvoie une seule valeur

```sql
CREATE OR ALTER FUNCTION dbo.fn_CalculerTrancheAge(@DateNaissance DATE)
RETURNS VARCHAR(10)
AS
BEGIN
    RETURN CASE
        WHEN DATEDIFF(YEAR, @DateNaissance, GETDATE()) < 30 THEN '<30'
        WHEN DATEDIFF(YEAR, @DateNaissance, GETDATE()) < 50 THEN '30-50'
        WHEN DATEDIFF(YEAR, @DateNaissance, GETDATE()) < 65 THEN '50-65'
        ELSE '65+'
    END;
END
```
**Utilisation** :
```sql
SELECT Nom, dbo.fn_CalculerTrancheAge(DateNaissance) AS Tranche FROM Clients;
```

**⚠️ Le piège de performance historique majeur (avant SQL Server 2019)** : une fonction scalaire appelée dans le `SELECT` d'une requête sur une grosse table est exécutée **ligne par ligne, comme une boucle cachée**, empêchant l'optimiseur de paralléliser ou d'estimer correctement le coût. Sur une table d'un million de lignes, ça peut transformer une requête de 2 secondes en 2 minutes.

**Depuis SQL Server 2019** : l'optimiseur peut "inline" certaines fonctions scalaires simples (celles sans effets de bord complexes), annulant en partie ce problème — c'est la fonctionnalité *Scalar UDF Inlining*. **Mais** : ne compte pas dessus systématiquement, certaines fonctions restent non-inlinables (celles avec du `TRY/CATCH`, des curseurs internes, des appels à d'autres objets...). **Réflexe pro** : sur une table volumineuse, préfère toujours transformer la logique en `CASE WHEN` inline (comme dans notre procédure `usp_ChargerDimClient`) plutôt qu'une fonction scalaire, sauf si tu es certain d'être en 2019+ et que la fonction est simple.

### Fonction table en ligne (Inline Table-Valued Function — iTVF) — la plus performante

```sql
CREATE OR ALTER FUNCTION dbo.fn_ContratsParClient(@ClientId INT)
RETURNS TABLE
AS
RETURN (
    SELECT ContratKey, NumeroContrat, CodeProduit, Statut
    FROM DimContrat
    WHERE ClientId = @ClientId
);
```
**Utilisation, comme une table** :
```sql
SELECT * FROM dbo.fn_ContratsParClient(42);

-- Ou en jointure, avec CROSS APPLY (voir plus bas)
SELECT cl.Nom, ct.NumeroContrat
FROM Clients cl
CROSS APPLY dbo.fn_ContratsParClient(cl.ClientId) ct;
```
**Pourquoi c'est performant** : une iTVF est en réalité une **simple requête paramétrée** que SQL Server **intègre directement dans le plan d'exécution global** de la requête appelante — pas d'exécution "ligne par ligne" cachée comme les fonctions scalaires. **C'est le type de fonction table à privilégier systématiquement** quand tu as besoin de logique réutilisable et paramétrée.

### Fonction table multi-instructions (Multi-Statement TVF) — à éviter si possible

```sql
CREATE OR ALTER FUNCTION dbo.fn_StatistiquesContrat(@ContratId INT)
RETURNS @Resultat TABLE (NbMouvements INT, Total DECIMAL(19,4))
AS
BEGIN
    INSERT INTO @Resultat
    SELECT COUNT(*), SUM(Montant)
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
    WHERE dc.ContratId = @ContratId;

    RETURN;
END
```
**Pourquoi l'éviter quand possible** : contrairement à l'iTVF, celle-ci a un **corps de plusieurs instructions** (`BEGIN...END`), ce qui empêche SQL Server de l'intégrer dans le plan global — elle est exécutée comme une **boîte noire séparée**, avec des estimations de cardinalité souvent très mauvaises (SQL Server suppose souvent un nombre fixe de lignes en sortie, indépendamment du vrai volume). **Si ta logique est trop complexe pour une iTVF simple**, préfère souvent une procédure stockée classique.

### APPLY — CROSS APPLY et OUTER APPLY

**Le problème que ça résout** : `JOIN` classique ne permet pas d'appeler une fonction/sous-requête **paramétrée par une colonne de la ligne courante**. `APPLY` le permet.

```sql
-- Pour chaque client, ses 3 derniers mouvements (via une iTVF)
SELECT cl.Nom, m.DateOperation, m.Montant
FROM Clients cl
CROSS APPLY (
    SELECT TOP 3 f.DateOperation, f.Montant
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
    WHERE dc.ClientId = cl.ClientId
    ORDER BY f.DateOperation DESC
) m;
```
**`CROSS APPLY`** se comporte comme un `INNER JOIN` (exclut les clients sans résultat). **`OUTER APPLY`** se comporte comme un `LEFT JOIN` (garde tous les clients, avec NULL si pas de résultat). **Cas d'usage classique** : "top N par groupe" avec logique complexe, appel de fonction table paramétrée par ligne — un des outils les plus puissants et sous-utilisés de T-SQL.

### Exercice 8.1

Explique pourquoi cette fonction scalaire serait risquée en performance sur une table de 5 millions de lignes, et propose une alternative.
```sql
CREATE FUNCTION dbo.fn_NomComplet(@Nom VARCHAR(50), @Prenom VARCHAR(50))
RETURNS VARCHAR(101)
AS
BEGIN
    RETURN @Prenom + ' ' + @Nom;
END
-- utilisée ainsi :
SELECT dbo.fn_NomComplet(Nom, Prenom) FROM Clients;  -- 5 millions de lignes
```

<details>
<summary>Corrigé</summary>

Même si la logique est triviale, avant SQL Server 2019 (et parfois même après, selon la complexité perçue), cette fonction scalaire s'exécute **ligne par ligne** sans possibilité de parallélisation, ce qui peut être très lent sur 5 millions de lignes. **Alternative** : inline directement l'expression dans la requête :
```sql
SELECT Prenom + ' ' + Nom AS NomComplet FROM Clients;
```
Pas de fonction du tout — l'expression est directement dans le SELECT, optimisée nativement par le moteur.
</details>

---

## Chapitre 9 — Boucles, curseurs, et pourquoi les éviter

### Le changement de mentalité le plus important de ce cours

SQL est un langage **déclaratif orienté ensembles** ("set-based") — tu décris **quel résultat** tu veux, pas **comment** l'obtenir pas à pas. C#, en comparaison, est **procédural** — tu décris chaque étape séquentielle.

**Le piège n°1 des développeurs venant du monde procédural (exactement ton cas, venant de C#)** : reproduire des boucles `for`/`foreach` en SQL, alors que 95% du temps, une requête basée sur des ensembles (jointures, agrégations, window functions) fait la même chose, en bien plus rapide.

### WHILE — la boucle T-SQL de base

```sql
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    PRINT @i;
    SET @i = @i + 1;
END
```
**Quand c'est légitime** : traitement par lots (batch processing) pour éviter de verrouiller une trop grosse quantité de lignes d'un coup :
```sql
-- Supprimer par lots de 1000 pour ne pas bloquer la table trop longtemps
WHILE 1 = 1
BEGIN
    DELETE TOP (1000) FROM FactMouvements_Archive WHERE DateOperation < '2015-01-01';
    IF @@ROWCOUNT = 0 BREAK;
END
```
C'est un usage **légitime et courant** en RUN de production — évite qu'une suppression massive ne bloque toute la table pendant de longues minutes en une seule transaction géante.

### CURSOR — la boucle ligne par ligne sur un résultat de requête

```sql
DECLARE @ContratId INT, @Montant DECIMAL(19,4);

DECLARE curseur CURSOR FOR
    SELECT ContratId, Montant FROM Contrats WHERE Statut = 'Actif';

OPEN curseur;
FETCH NEXT FROM curseur INTO @ContratId, @Montant;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- traitement ligne par ligne...
    EXEC dbo.usp_CalculerQuelqueChose @ContratId;

    FETCH NEXT FROM curseur INTO @ContratId, @Montant;
END

CLOSE curseur;
DEALLOCATE curseur;
```

**Pourquoi les curseurs ont mauvaise réputation** : ils traitent les données **une ligne à la fois**, ce qui va radicalement à l'encontre de la façon dont le moteur relationnel est optimisé (traitement par ensembles, en masse). Sur une table de 100 000 lignes, un curseur peut être **100 à 1000 fois plus lent** qu'une requête équivalente basée sur des ensembles.

**Quand un curseur est parfois justifié (rare)** :
- Tu dois appeler une **procédure stockée externe** pour chaque ligne, sans possibilité de la réécrire en set-based (souvent parce qu'elle appelle un service externe, ou fait des opérations qui n'ont pas d'équivalent ensembliste).
- Une logique **vraiment séquentielle** où chaque ligne dépend du résultat de la précédente d'une manière qui ne peut pas s'exprimer avec des window functions.

**Dans 95% des cas où tu es tenté d'écrire un curseur, la question à te poser est** : « est-ce que je peux exprimer ça avec une jointure, un GROUP BY, ou une window function ? » — presque toujours, la réponse est oui.

### Exemple de transformation curseur → set-based

**Version curseur (à éviter)** :
```sql
DECLARE @ClientId INT, @Ville NVARCHAR(50);
DECLARE curseur CURSOR FOR SELECT ClientId, Ville FROM Clients;
OPEN curseur;
FETCH NEXT FROM curseur INTO @ClientId, @Ville;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE Clients SET Ville = UPPER(@Ville) WHERE ClientId = @ClientId;
    FETCH NEXT FROM curseur INTO @ClientId, @Ville;
END
CLOSE curseur; DEALLOCATE curseur;
```
**Version set-based (à privilégier, des ordres de grandeur plus rapide)** :
```sql
UPDATE Clients SET Ville = UPPER(Ville);
```
**C'est le même résultat**, en une seule instruction, sans boucle explicite — le moteur SQL Server traite en interne toutes les lignes concernées de manière optimisée et parallélisable.

### Exercice 9.1

Transforme ce curseur en requête set-based :
```sql
DECLARE @ContratId INT;
DECLARE curseur CURSOR FOR SELECT ContratId FROM Contrats WHERE Statut = 'Actif';
OPEN curseur;
FETCH NEXT FROM curseur INTO @ContratId;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE Contrats SET DateModification = GETDATE() WHERE ContratId = @ContratId;
    FETCH NEXT FROM curseur INTO @ContratId;
END
CLOSE curseur; DEALLOCATE curseur;
```

<details>
<summary>Corrigé</summary>

```sql
UPDATE Contrats
SET DateModification = GETDATE()
WHERE Statut = 'Actif';
```
Aucune boucle nécessaire — `UPDATE` s'applique nativement à toutes les lignes correspondant au `WHERE`.
</details>

---

# PARTIE 4 — PERFORMANCE ET MOTEUR INTERNE

## Chapitre 10 — Index, le guide complet

### Pourquoi un index existe — l'analogie qu'on a déjà vue

Sans index, chercher une ligne dans une table demande de la parcourir entièrement (**Table Scan**). Un index construit une structure organisée (arbre B-Tree) qui permet de retrouver l'information directement, comme l'index d'un livre — rappel de notre analogie sur la recherche dichotomique O(log n).

### Clustered Index — l'organisation physique

```sql
CREATE CLUSTERED INDEX IX_Contrats_ContratId ON Contrats(ContratId);
```
**Une seule par table**, parce qu'il **réorganise physiquement** les données sur le disque selon cet ordre. Quand tu déclares une `PRIMARY KEY`, SQL Server crée **automatiquement** un clustered index dessus, sauf indication contraire.

**Analogie** : c'est comme un dictionnaire papier — les mots sont physiquement rangés par ordre alphabétique sur les pages. Il ne peut y avoir qu'un seul ordre physique possible pour un livre donné.

**Une table sans clustered index s'appelle un "heap"** (tas) — les lignes sont stockées sans ordre particulier, ce qui est généralement **moins performant** pour la plupart des requêtes (sauf cas très spécifiques d'insertion massive pure sans lecture).

### Non-Clustered Index — l'index secondaire

```sql
CREATE INDEX IX_Contrats_ClientId ON Contrats(ClientId);
```
**Plusieurs possibles par table** (jusqu'à 999 en théorie, en pratique on en met rarement plus de 5-10). C'est une structure **séparée** qui contient la colonne indexée + un pointeur vers la ligne complète (soit la clé du clustered index, soit un RID si la table est un heap).

**Analogie** : c'est comme l'index alphabétique par sujet à la fin d'un livre technique — une liste organisée séparément qui te renvoie à la bonne page, sans que le contenu du livre lui-même soit réorganisé.

### Index couvrant (Covering Index) — l'optimisation avancée

```sql
CREATE INDEX IX_Contrats_ClientId_Covering
ON Contrats(ClientId)
INCLUDE (NumeroContrat, CodeProduit, Statut);
```
**Le problème que ça résout** : si ta requête fait `SELECT NumeroContrat, CodeProduit FROM Contrats WHERE ClientId = 42`, un index simple sur `ClientId` trouve rapidement les lignes concernées, mais doit ensuite faire un **"Key Lookup"** (aller chercher les colonnes manquantes dans la table principale) — une étape supplémentaire coûteuse répétée pour chaque ligne trouvée.

**Avec `INCLUDE`**, les colonnes supplémentaires sont **stockées directement dans l'index** (mais pas utilisées pour le tri/recherche, juste "embarquées") — la requête peut être **entièrement satisfaite depuis l'index**, sans jamais toucher la table principale. C'est ce qu'on appelle une requête "couverte" — visible dans le plan d'exécution comme *Index Seek* sans *Key Lookup* associé.

**Quand l'utiliser** : sur les requêtes fréquentes et critiques en performance où tu connais à l'avance les colonnes exactes demandées.

### Index filtré (Filtered Index) — indexer seulement un sous-ensemble

```sql
CREATE INDEX IX_Contrats_Actifs
ON Contrats(ClientId)
WHERE Statut = 'Actif';
```
**Pourquoi** : si 95% de tes requêtes filtrent sur `Statut = 'Actif'`, indexer uniquement ce sous-ensemble donne un index **plus petit, plus rapide à maintenir, et plus efficace** que d'indexer toute la table (y compris les contrats Rachetés/Décès qu'on interroge rarement).

### Index unique — contrainte + performance

```sql
CREATE UNIQUE INDEX IX_Contrats_NumeroContrat ON Contrats(NumeroContrat);
```
Garantit l'unicité **et** sert d'index performant pour les recherches — deux bénéfices en une seule structure.

### Index composite — plusieurs colonnes, et l'ordre compte ÉNORMÉMENT

```sql
CREATE INDEX IX_Mouvements_Contrat_Date ON FactMouvements(ContratKey, DateKey);
```
**Règle fondamentale à bien comprendre** : un index composite est utile pour filtrer sur la **première colonne seule**, ou sur la **première + suivantes dans l'ordre**, mais **pas efficacement** sur la deuxième colonne seule.

```sql
WHERE ContratKey = 5                         -- ✅ utilise bien l'index
WHERE ContratKey = 5 AND DateKey = 20260101  -- ✅ utilise bien l'index (les deux colonnes, dans l'ordre)
WHERE DateKey = 20260101                     -- ❌ n'utilise PAS efficacement cet index (2e colonne seule)
```
**Analogie** : c'est comme un annuaire téléphonique trié par Nom puis Prénom. Chercher "MARTIN" est rapide (première colonne). Chercher "tous les Jean, peu importe le nom" **oblige à parcourir tout l'annuaire** — le tri par Prénom seul n'existe pas dans cette structure.

**Conséquence pratique** : quand tu crées un index composite, **mets en premier la colonne la plus souvent utilisée seule en filtre**, et les autres colonnes dans l'ordre de sélectivité décroissante généralement.

### Le prix à payer — index et écritures

Chaque `INSERT`/`UPDATE`/`DELETE` doit mettre à jour **tous les index concernés** de la table, pas seulement les données. **Plus tu as d'index, plus les écritures sont lentes.** C'est un compromis permanent lecture/écriture que tu dois arbitrer selon le profil de la table (une table très lue et peu écrite mérite plus d'index qu'une table de logs à haute fréquence d'écriture, par exemple).

### Fragmentation d'index — la maintenance nécessaire

Après beaucoup d'insertions/suppressions, les pages de l'index se fragmentent (désorganisées physiquement), dégradant la performance.

```sql
-- Vérifier la fragmentation
SELECT
    OBJECT_NAME(ips.object_id) AS Table_Name,
    i.name AS Index_Name,
    ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.avg_fragmentation_in_percent > 10
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Réorganiser (léger, en ligne) si fragmentation entre 10-30%
ALTER INDEX IX_Contrats_ClientId ON Contrats REORGANIZE;

-- Reconstruire (plus lourd, potentiellement bloquant) si fragmentation > 30%
ALTER INDEX IX_Contrats_ClientId ON Contrats REBUILD;
```
**C'est exactement le type de maintenance qu'un job planifié fait régulièrement dans un environnement de production comme le tien** — bon réflexe à avoir pendant ton transfert de compétence : demander s'il existe un job de maintenance d'index, et à quelle fréquence.

### Comment savoir quel index créer — les DMV utiles

```sql
-- Index manquants suggérés par SQL Server lui-même (basé sur l'historique des requêtes)
SELECT
    mid.statement AS Table_Concernee,
    migs.avg_user_impact,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_group_stats_query migs
    ON migs.group_handle = (SELECT TOP 1 group_handle FROM sys.dm_db_missing_index_groups WHERE index_handle = mid.index_handle)
ORDER BY migs.avg_user_impact DESC;
```
**⚠️ Attention** : ces suggestions sont des **indices**, pas des vérités absolues — SQL Server ne connaît pas le coût en écriture, ni les index déjà redondants. **Ne jamais créer un index automatiquement sans réfléchir** — vérifie toujours s'il ne fait pas doublon avec un index existant.

### Exercice 10.1

Une requête fréquente est :
```sql
SELECT NumeroContrat, DateSouscription FROM Contrats WHERE ClientId = @Id AND Statut = 'Actif';
```
Propose un index adapté, en justifiant l'ordre des colonnes et l'usage éventuel d'INCLUDE.

<details>
<summary>Corrigé</summary>

```sql
CREATE INDEX IX_Contrats_ClientId_Statut
ON Contrats(ClientId, Statut)
INCLUDE (NumeroContrat, DateSouscription);
```
- `ClientId` en premier : c'est le filtre le plus sélectif et systématiquement utilisé.
- `Statut` en second : filtré ensemble avec `ClientId` dans la même requête (les deux colonnes dans le WHERE avec AND).
- `INCLUDE` sur `NumeroContrat` et `DateSouscription` : ce sont les colonnes du SELECT, non utilisées pour filtrer — les inclure évite le Key Lookup, rendant la requête entièrement "couverte" par l'index.
</details>

---

## Chapitre 11 — Lire un plan d'exécution

### Comment l'obtenir

Dans SSMS : bouton **"Afficher le plan d'exécution réel"** (Ctrl+M) avant d'exécuter, ou `SET STATISTICS IO, TIME ON` pour des chiffres textuels précis.

### Les opérateurs à connaître absolument

| Opérateur | Signification | Bon ou mauvais signe ? |
|---|---|---|
| **Table Scan** | Parcourt toute la table (heap) | 🔴 Souvent mauvais signe sur une grosse table |
| **Clustered Index Scan** | Parcourt tout le clustered index | 🔴 Souvent mauvais signe (équivalent d'un scan complet) |
| **Index Seek** | Va directement chercher via l'index | 🟢 Excellent signe |
| **Key Lookup** | Va chercher des colonnes manquantes dans la table après un Seek sur un index secondaire | 🟡 Acceptable en petit volume, problématique répété des milliers de fois |
| **Nested Loops** | Boucle une table dans l'autre pour la jointure | 🟢 Bon pour petits volumes, 🔴 mauvais si les deux côtés sont énormes |
| **Hash Match** | Construit une table de hachage pour la jointure | 🟢 Bon pour gros volumes sans index approprié |
| **Merge Join** | Fusionne deux entrées déjà triées | 🟢 Très efficace quand les données sont déjà triées (ex: sur clé d'index) |
| **Sort** | Trie explicitement les données | 🟡 Coûteux, surveille s'il peut être évité par un index |

### Lire les pourcentages de coût

Chaque opérateur affiche un **pourcentage du coût total estimé** de la requête. **Concentre-toi toujours sur l'opérateur avec le plus gros pourcentage** — c'est le goulot d'étranglement principal, inutile d'optimiser un opérateur à 2% du coût total.

### SET STATISTICS IO / TIME — les chiffres bruts

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM FactMouvements WHERE ContratKey = 42;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```
Renvoie dans l'onglet **Messages** :
```
Table 'FactMouvements'. Scan count 1, logical reads 1520, physical reads 0...
CPU time = 15 ms, elapsed time = 18 ms.
```
**`logical reads`** est la métrique la plus stable à surveiller (indépendante du cache) : le nombre de pages de 8 Ko lues. **Comparer le `logical reads` avant/après un ajout d'index** est LA méthode la plus fiable pour valider objectivement qu'une optimisation fonctionne — plus fiable que le simple temps chronométré, qui varie selon la charge du serveur au moment du test.

### Estimé vs Réel — un piège de diagnostic classique

Le plan **estimé** (sans exécuter) utilise les **statistiques** (vues au chapitre suivant) pour deviner le nombre de lignes. Le plan **réel** (après exécution) montre le nombre de lignes **vraiment** traitées. **Un grand écart entre les deux est un signal d'alarme majeur** — ça indique typiquement des statistiques obsolètes, ou le fameux paramètre sniffing (déjà vu ensemble) : SQL Server a choisi un plan basé sur une hypothèse fausse.

### Exercice 11.1

Tu observes un `Clustered Index Scan` sur une table de 5 millions de lignes pour une requête qui filtre sur `ClientId = 42`. Que suspectes-tu, et que vérifies-tu en premier ?

<details>
<summary>Corrigé</summary>

Il manque très probablement un **index non-clustered sur `ClientId`** — sans lui, SQL Server doit parcourir l'intégralité du clustered index pour trouver les lignes correspondantes, au lieu de faire un `Index Seek` direct. Premier réflexe : vérifier les index existants sur la table (`sp_helpindex NomTable` ou l'explorateur d'objets SSMS), et si absent, envisager `CREATE INDEX IX_Table_ClientId ON Table(ClientId)` — en confirmant d'abord via `SET STATISTICS IO` avant/après que ça améliore vraiment la situation.
</details>

---

## Chapitre 12 — Statistiques et paramètre sniffing

### Que sont les statistiques SQL Server

Ce sont des **résumés de la distribution des valeurs** dans une colonne (nombre de lignes, valeurs distinctes, histogramme de répartition), que l'**optimiseur** utilise pour estimer le coût de chaque plan possible et choisir le meilleur.

```sql
-- Voir les statistiques existantes sur une table
DBCC SHOW_STATISTICS ('Contrats', 'IX_Contrats_ClientId');

-- Forcer une mise à jour manuelle (normalement automatique, mais utile en diagnostic)
UPDATE STATISTICS Contrats;
```
**Statistiques obsolètes** = principale cause de mauvais plans d'exécution après une grosse évolution de volumétrie (import massif, migration de données — exactement ton contexte de mission en phase de garantie).

### Le paramètre sniffing (rappel approfondi)

**Le phénomène** : SQL Server **compile un plan une seule fois** pour une procédure stockée, basé sur les **premières valeurs de paramètres** utilisées lors de cette compilation. Ce plan est ensuite **réutilisé (mis en cache)** pour tous les appels suivants, même avec des paramètres très différents.

**Exemple concret du problème** :
```sql
CREATE PROCEDURE dbo.usp_ContratsParClient @ClientId INT
AS
SELECT * FROM Contrats WHERE ClientId = @ClientId;
```
Si le premier appel est `@ClientId = 1` (client avec 2 contrats), SQL Server compile un plan optimisé pour un **petit** résultat (probablement un Index Seek + Nested Loop). Si un appel suivant est `@ClientId = 999` (un client fictif "agrégateur" avec 500 000 contrats), **ce même plan sous-optimal est réutilisé**, avec des performances catastrophiques.

### Solutions au paramètre sniffing

```sql
-- Option 1 : forcer une recompilation à chaque exécution (coût de compilation à chaque appel, mais plan toujours adapté)
CREATE PROCEDURE dbo.usp_ContratsParClient @ClientId INT
AS
SELECT * FROM Contrats WHERE ClientId = @ClientId
OPTION (RECOMPILE);

-- Option 2 : optimiser pour une valeur "moyenne" plutôt que la première rencontrée
SELECT * FROM Contrats WHERE ClientId = @ClientId
OPTION (OPTIMIZE FOR UNKNOWN);

-- Option 3 : variable locale pour "casser" le sniffing (astuce classique)
CREATE PROCEDURE dbo.usp_ContratsParClient @ClientId INT
AS
DECLARE @ClientIdLocal INT = @ClientId;
SELECT * FROM Contrats WHERE ClientId = @ClientIdLocal;
```
**L'astuce de la variable locale** fonctionne parce que SQL Server ne peut pas "sniffer" (deviner) la valeur d'une variable locale de la même façon qu'un paramètre — il utilise alors une estimation basée sur la distribution moyenne des statistiques, plus stable dans le temps mais parfois moins optimale pour un cas précis.

**Quelle solution choisir** : dépend du contexte — `RECOMPILE` coûte un peu de CPU à chaque appel mais garantit le meilleur plan systématiquement (bon pour des procédures peu appelées mais avec des paramètres très variables). La variable locale est un compromis léger et courant. **C'est exactement le genre d'arbitrage qu'un DBA/dev senior discute en équipe** — pose la question à Jean-François s'il rencontre ce problème sur vos procédures d'extraction.

### Exercice 12.1

Une procédure stockée est rapide le matin, mais devient très lente l'après-midi sans changement de code. Que suspectes-tu en premier, et quelles 2 actions de diagnostic fais-tu ?

<details>
<summary>Corrigé</summary>

Suspect n°1 : **paramètre sniffing** — le plan a probablement été mis en cache tôt le matin avec des paramètres non représentatifs, et un job/traitement a "vidé" ou recompilé le cache entre temps avec un paramètre atypique.

Actions de diagnostic :
1. Comparer le plan **estimé** vs **réel** de la procédure avec les paramètres du moment — un grand écart de nombre de lignes confirme le sniffing.
2. Vérifier `sys.dm_exec_query_stats` pour voir l'historique des exécutions de cette procédure et la variabilité du nombre de lignes traitées selon l'heure/les paramètres.

Solution probable : ajouter `OPTION (RECOMPILE)` ou la technique de variable locale.
</details>

---

*(La formation se poursuit avec la Partie 5 — Stockage, partitionnement et verrouillage — puis la Partie 6 — Méthodologie et exercices de synthèse.)*
