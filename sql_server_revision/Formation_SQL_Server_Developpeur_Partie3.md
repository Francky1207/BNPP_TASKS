# Formation SQL Server — Partie 3 : Stockage, Partitionnement, Méthodologie

*(Suite directe des Parties 1 et 2 — Chapitres 13 à 18)*

---

# PARTIE 5 — STOCKAGE ET ARCHITECTURE PHYSIQUE

## Chapitre 13 — Fichiers, filegroups et tempdb

### Les fichiers physiques d'une base de données

Chaque base SQL Server repose sur **au minimum 2 fichiers physiques** sur le disque :

| Fichier | Extension | Rôle |
|---|---|---|
| **Fichier de données primaire** | `.mdf` | Contient les tables, index, données — le cœur de la base |
| **Fichiers de données secondaires** (optionnels) | `.ndf` | Extensions du fichier primaire, pour répartir sur plusieurs disques |
| **Fichier journal (log)** | `.ldf` | Enregistre **chaque transaction** avant qu'elle ne soit appliquée — le "transaction log" |

**Voir les fichiers d'une base** :
```sql
SELECT
    name AS NomFichier,
    physical_name AS CheminDisque,
    type_desc AS Type,
    size * 8 / 1024 AS TailleMo
FROM sys.database_files;
```

### Pourquoi le fichier .ldf (journal) est critique à comprendre

**Toute modification de données passe d'abord par le journal** avant d'être appliquée aux fichiers de données — c'est le mécanisme qui garantit la **Durabilité** de ACID (rappel de nos échanges précédents). Si le serveur crash en plein milieu d'une transaction, SQL Server peut **rejouer ou annuler** grâce au journal, pour revenir à un état cohérent.

**Le mode de récupération (Recovery Model)** détermine la gestion du journal :
```sql
SELECT name, recovery_model_desc FROM sys.databases;
```
- **SIMPLE** : le journal est automatiquement vidé après chaque checkpoint — pas de sauvegarde de journal possible, restauration seulement au dernier backup complet. Utilisé souvent pour des bases de dev/test ou d'entrepôt rechargé entièrement chaque nuit (**ton cas SEEDVIE_STG/DWH pourrait légitimement être en SIMPLE**, puisque tu rechargeais tout à chaque batch).
- **FULL** : le journal grossit jusqu'à sauvegarde explicite — permet une restauration **point-in-time** précise, indispensable pour une base de production critique où chaque transaction compte (typiquement ta base de production Cardif).
- **BULK_LOGGED** : compromis, pour optimiser certaines opérations de masse.

**Piège classique en RUN** : un fichier `.ldf` qui grossit anormalement, souvent parce que le mode est en FULL mais que **personne ne fait de sauvegarde de journal** régulière — le journal ne se vide jamais. **Symptôme typique** : disque qui se remplit progressivement sans raison apparente. **Diagnostic** :
```sql
SELECT name, log_reuse_wait_desc FROM sys.databases;
```
`log_reuse_wait_desc` te dit **pourquoi** le journal ne peut pas être réutilisé/vidé (souvent `LOG_BACKUP` = en attente d'une sauvegarde de journal).

### Filegroups — organiser physiquement les données

```sql
ALTER DATABASE SEEDVIE_DWH ADD FILEGROUP FG_Archive;

ALTER DATABASE SEEDVIE_DWH
ADD FILE (
    NAME = 'SEEDVIE_Archive',
    FILENAME = 'D:\SQLData\SEEDVIE_Archive.ndf',
    SIZE = 500MB
) TO FILEGROUP FG_Archive;
```
**Pourquoi séparer en filegroups** :
- **Répartir la charge disque** — mettre les tables très sollicitées sur un disque rapide (SSD), et les données d'archive rarement consultées sur un disque plus lent/économique.
- **Faciliter les sauvegardes partielles** — sauvegarder uniquement le filegroup "actif" fréquemment, et le filegroup "archive" (qui ne change jamais) beaucoup plus rarement.
- **Prérequis technique pour le partitionnement physique multi-disque** (voir chapitre suivant).

### tempdb — la base système à ne jamais négliger

**Ce que c'est** : une base système partagée par **toute l'instance** SQL Server (pas juste ta base), utilisée en interne pour :
- Les tables temporaires (`#temp`, vues au chapitre 4).
- Les tris volumineux qui ne tiennent pas en mémoire (`ORDER BY`, `GROUP BY` sur gros volumes).
- Les opérations de hachage (`Hash Match` vu dans les plans d'exécution).
- Le versioning de lignes (RCSI, isolation Snapshot vue dans nos échanges précédents).
- Les variables table de grande taille.

**Pourquoi c'est souvent un goulot d'étranglement en production** : **toutes les bases et sessions de l'instance se partagent le même tempdb**. Une requête mal optimisée qui fait un gros tri quelque part peut ralentir tempdb pour **tout le monde**, y compris tes traitements ETL qui n'ont rien à voir.

**Bonne pratique standard (à vérifier en mission)** : tempdb doit avoir **plusieurs fichiers de données de taille égale** (souvent autant que de cœurs CPU, jusqu'à 8), pour réduire la contention interne. C'est un des premiers points qu'un DBA vérifie sur un serveur qui rame.

```sql
-- Vérifier la configuration actuelle de tempdb
SELECT name, physical_name, size * 8 / 1024 AS TailleMo
FROM tempdb.sys.database_files;
```

### Exercice 13.1

Un job d'extraction nocturne échoue une nuit sur deux avec une erreur de type "espace disque insuffisant sur le journal". Que vérifies-tu en premier, et pourquoi ?

<details>
<summary>Corrigé</summary>

Premier réflexe : vérifier le **Recovery Model** de la base (`FULL` probablement) et le **`log_reuse_wait_desc`** via `sys.databases`. Si le résultat est `LOG_BACKUP`, ça confirme qu'aucune sauvegarde de journal régulière n'est planifiée, laissant le `.ldf` grossir indéfiniment jusqu'à saturer le disque. Solution : soit planifier des sauvegardes de journal régulières (toutes les 15-30 min typiquement en prod), soit repasser en `SIMPLE` si la base ne nécessite pas de restauration point-in-time (à valider avec l'équipe/DBA avant de changer quoi que ce soit en prod !).
</details>

---

## Chapitre 14 — Le partitionnement (le sujet qui t'a bloqué)

**On y voilà.** Prends ton temps sur ce chapitre — c'est celui que tu as explicitement demandé de bien comprendre.

### D'abord, clarifier une confusion fréquente : 3 sens différents du mot "partitionnement"

Ton collègue a peut-être mélangé (volontairement ou non) plusieurs concepts qui portent des noms proches. Voici les 3 à bien distinguer :

1. **Le partitionnement de table** (Table Partitioning) — diviser **une seule table** en plusieurs segments internes selon une valeur (souvent une date), tout en la faisant apparaître comme **une seule table** aux yeux des requêtes. **C'est le sens le plus probable de ce dont parlait ton collègue.**

2. **Le partitionnement de disque physique** — répartir les fichiers de la base sur plusieurs volumes/disques physiques distincts (via les filegroups vus au chapitre 13) pour la performance I/O.

3. **Le partitionnement au sens système d'exploitation** — les partitions de disque Windows/Linux (C:\, D:\...) — un sujet d'administration système, pas de développement SQL, mais qui peut aussi faire partie d'une conversation "disque" avec ton collègue s'il parlait d'infra serveur.

### Le partitionnement de table en détail — le concept clé

**Le problème que ça résout** : une table de plusieurs centaines de millions de lignes (typiquement une table de mouvements/transactions sur des années d'historique) devient difficile à gérer :
- Les requêtes qui ne portent que sur le mois courant doivent quand même "connaître" l'existence de toute la table.
- La maintenance (reconstruction d'index, sauvegardes) devient très lourde sur l'ensemble.
- L'archivage/purge des vieilles données nécessite un `DELETE` massif, lent et bloquant (rappel du chapitre 9 sur le `WHILE` par lots).

**Le partitionnement découpe la table en tranches physiques** (souvent par plage de dates : un mois = une partition), tout en la présentant comme **une seule table logique**. Une requête qui filtre sur une plage de dates peut alors **ignorer complètement** les partitions hors de cette plage — c'est ce qu'on appelle le **"partition elimination"** (élimination de partitions), un gain de performance considérable.

### Analogie pour bien ancrer le concept

Imagine un immense entrepôt de dossiers papier (ta table). Sans partitionnement, c'est **une seule pièce géante** où tous les dossiers de tous les mois de tous les ans sont mélangés — chercher les dossiers de janvier 2026 demande de fouiller toute la pièce.

Avec le partitionnement, l'entrepôt est divisé en **plusieurs pièces séparées, une par mois**, mais avec une signalétique commune (un seul "entrepôt" du point de vue de l'utilisateur qui vient chercher un dossier). Chercher les dossiers de janvier 2026 ? Tu vas **directement dans la pièce "Janvier 2026"**, sans même ouvrir la porte des autres pièces. Et si tu dois détruire les dossiers de 2015 (archivage), tu **vides et fermes une pièce entière d'un coup**, plutôt que de fouiller dossier par dossier dans la pièce géante.

### Comment ça marche techniquement — les 3 éléments

**1. La fonction de partition** — définit **où** sont les frontières entre partitions :
```sql
CREATE PARTITION FUNCTION PF_ParAnnee (DATE)
AS RANGE RIGHT FOR VALUES ('2024-01-01', '2025-01-01', '2026-01-01', '2027-01-01');
```
**Décryptage** : ça crée 5 tranches — avant 2024, 2024, 2025, 2026, après 2027.

**`RANGE RIGHT` vs `RANGE LEFT`** — détermine de quel côté de la frontière va la valeur limite exacte :
- `RANGE RIGHT` : la valeur `2025-01-01` va dans la partition qui **commence** à cette date (partition "2025").
- `RANGE LEFT` : la valeur `2025-01-01` va dans la partition qui **se termine** à cette date (partition "2024").
**`RANGE RIGHT` est la convention la plus intuitive pour des dates** (le 1er janvier appartient à la nouvelle année), donc la plus utilisée en pratique.

**2. Le schéma de partition** — définit **où physiquement** (quel filegroup) chaque tranche est stockée :
```sql
CREATE PARTITION SCHEME PS_ParAnnee
AS PARTITION PF_ParAnnee
ALL TO ([PRIMARY]);   -- ici, tout sur le même filegroup pour simplifier
-- en prod, on mettrait souvent un filegroup différent par tranche pour répartir sur plusieurs disques
```

**3. La table créée sur ce schéma** :
```sql
CREATE TABLE FactMouvements_Partitionnee (
    MouvementKey BIGINT IDENTITY(1,1),
    DateOperation DATE NOT NULL,
    ContratKey INT NOT NULL,
    Montant DECIMAL(19,4) NOT NULL
) ON PS_ParAnnee(DateOperation);   -- la colonne qui pilote le partitionnement
```

### Voir la répartition des données par partition

```sql
SELECT
    $PARTITION.PF_ParAnnee(DateOperation) AS NumeroPartition,
    COUNT(*) AS NbLignes,
    MIN(DateOperation) AS DateMin,
    MAX(DateOperation) AS DateMax
FROM FactMouvements_Partitionnee
GROUP BY $PARTITION.PF_ParAnnee(DateOperation)
ORDER BY NumeroPartition;
```
`$PARTITION.NomFonction(colonne)` est une fonction spéciale qui te dit dans **quelle partition numérotée** se trouve chaque ligne — outil de diagnostic indispensable.

### Le "partition elimination" — le bénéfice concret en plan d'exécution

```sql
SELECT SUM(Montant) FROM FactMouvements_Partitionnee
WHERE DateOperation BETWEEN '2026-01-01' AND '2026-12-31';
```
Dans le plan d'exécution, tu verras un attribut **"Actual Partition Count"** sur le scan — s'il affiche `1` alors que la table a 5 partitions au total, ça confirme que SQL Server a **complètement ignoré** les 4 autres partitions, sans même les lire. **C'est le signe que le partitionnement fonctionne comme prévu.**

### Le switch de partition — l'opération reine pour l'archivage rapide

**Le bénéfice le plus spectaculaire du partitionnement** : basculer une partition entière vers une autre table, **quasi instantanément**, quel que soit son volume (des millions de lignes basculées en une fraction de seconde) :

```sql
-- Créer une table d'archive avec EXACTEMENT la même structure
CREATE TABLE FactMouvements_Archive2024 (
    MouvementKey BIGINT,
    DateOperation DATE NOT NULL,
    ContratKey INT NOT NULL,
    Montant DECIMAL(19,4) NOT NULL
);

-- Bascule quasi-instantanée de la partition 2024 vers la table d'archive
ALTER TABLE FactMouvements_Partitionnee
SWITCH PARTITION 2 TO FactMouvements_Archive2024;
```
**Pourquoi c'est quasi-instantané** : contrairement à un `INSERT INTO ... SELECT` + `DELETE` qui **copie physiquement chaque ligne**, `SWITCH` ne fait que **changer un pointeur de métadonnées** — les pages de données ne bougent pas physiquement sur le disque, seule leur "appartenance logique" change. C'est une opération de l'ordre de la **milliseconde**, peu importe si la partition contient 10 lignes ou 500 millions.

**C'est exactement le mécanisme qu'utilisent les grandes entreprises pour l'archivage réglementaire** (rappel de ton contexte LCB-FT/Infocentre) — purger une année de données sans jamais bloquer la table principale pendant des heures avec un DELETE massif.

**Contrainte technique importante** : pour que `SWITCH` fonctionne, la table source et la table cible doivent avoir **une structure identique** (mêmes colonnes, mêmes types, mêmes index), et la partition source doit correspondre exactement aux données transférées (pas de ligne qui "déborderait" en dehors des bornes).

### Le partitionnement horizontal vs vertical — vocabulaire à connaître

- **Partitionnement horizontal** (celui vu ci-dessus) : diviser une table par **lignes** (certaines lignes dans une partition, d'autres dans une autre) — c'est le sens du "table partitioning" SQL Server.
- **Partitionnement vertical** : diviser une table par **colonnes** (certaines colonnes dans une table, d'autres dans une table liée) — un concept de modélisation différent, parfois utilisé pour séparer des colonnes rarement consultées (gros textes, blobs) des colonnes fréquemment lues.

### Quand partitionner (et quand ne pas le faire)

**Signaux qui justifient le partitionnement** :
- Table de plusieurs dizaines/centaines de millions de lignes.
- Les requêtes filtrent **très souvent** sur la colonne candidate au partitionnement (typiquement une date).
- Besoin d'archiver/purger régulièrement de grosses tranches de données.
- Besoin de répartir la charge I/O sur plusieurs disques physiques.

**Signaux qui disent NON** :
- Table de quelques centaines de milliers de lignes — le partitionnement ajoute de la **complexité de gestion** sans bénéfice mesurable.
- Les requêtes ne filtrent jamais sur une colonne cohérente qui permettrait l'elimination de partition.
- Pas de besoin d'archivage massif régulier.

**Le partitionnement n'est pas un outil "à mettre partout par principe"** — c'est un outil pour un problème précis (grosse volumétrie + accès par plage + besoin d'archivage). **En entretien ou en discussion avec ton collègue, cette nuance ("ça dépend du volume et du pattern d'accès") est exactement ce qui montre la maturité.**

### Le partitionnement au sens "disque physique" (2e sens du mot)

Rappel du chapitre 13 : en combinant filegroups + partitionnement de table, on peut faire en sorte que **chaque partition vive sur un disque physique différent** :

```sql
CREATE PARTITION SCHEME PS_ParAnnee
AS PARTITION PF_ParAnnee
TO (FG_Archive2024, FG_Archive2025, FG_Actif2026, FG_Actif2026);
```
**Bénéfice** : les données récentes (fréquemment consultées) peuvent vivre sur un disque SSD rapide et coûteux, tandis que les données anciennes (rarement consultées mais réglementairement conservées) vivent sur un disque plus lent et économique. **C'est probablement de ça que parlait ton collègue** en mentionnant "partitionnement disque" — la combinaison des deux concepts (table + filegroups physiques).

### Exercice 14.1

Ton équipe a une table `FactMouvements` de 200 millions de lignes, avec un historique de 15 ans. 95% des requêtes portent sur les 3 derniers mois. Chaque année, il faut purger l'année la plus ancienne pour respecter une politique de rétention réglementaire. Propose une stratégie de partitionnement, en justifiant la colonne choisie et la maille (mensuelle ? annuelle ?).

<details>
<summary>Corrigé</summary>

**Stratégie proposée** : partitionnement par `DateOperation`, avec une **maille mensuelle** (une partition par mois plutôt qu'annuelle).

**Justification de la colonne** : `DateOperation` est la colonne systématiquement filtrée par les requêtes (95% portent sur les 3 derniers mois) — elle permet le meilleur "partition elimination".

**Justification de la maille mensuelle plutôt qu'annuelle** :
- Plus fine = elimination de partition plus précise (une requête sur "le mois dernier" élimine 179 des 180 partitions sur 15 ans, contre 14 des 15 en maille annuelle).
- La purge réglementaire "par année" peut se faire en **switchant 12 partitions mensuelles** d'un coup (toujours quasi-instantané), donc la maille plus fine n'empêche pas la purge annuelle — elle l'affine même, permettant potentiellement une purge plus granulaire si le besoin évolue (ex: passer à une rétention de 10 ans et 6 mois plutôt que 10 ans pile).

**Combiné avec des filegroups** : mettre les 3-4 derniers mois sur un filegroup rapide (SSD), et le reste sur un filegroup plus économique — cohérent avec le pattern d'accès observé (95% sur les 3 derniers mois).
</details>

---

## Chapitre 15 — Verrouillage et niveaux d'isolation approfondis

### Rappel des niveaux (déjà vus, on approfondit le mécanisme)

Le verrouillage (**locking**) est le mécanisme qui empêche deux transactions concurrentes de se marcher dessus. Chaque niveau d'isolation (Read Committed, Repeatable Read, Serializable, Snapshot) définit **combien de temps et sur quoi** les verrous sont posés.

### Les types de verrous principaux

| Type | Nom | Comportement |
|---|---|---|
| **S** | Shared (partagé) | Plusieurs transactions peuvent lire en même temps |
| **X** | Exclusive | Une seule transaction peut écrire, bloque tout le reste |
| **U** | Update | Utilisé pendant qu'on décide si on va modifier, évite les deadlocks entre deux U simultanés |
| **IS/IX** | Intent Shared/Exclusive | Signale l'intention à un niveau supérieur (table) qu'un verrou existe en dessous (ligne/page) |

### Voir les verrous actifs

```sql
SELECT
    request_session_id AS SessionId,
    resource_type,
    resource_database_id,
    request_mode,
    request_status
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID();
```
**Cas d'usage direct pour toi** : si un job d'extraction reste bloqué mystérieusement, cette requête (ou `sp_who2`, plus simple d'accès) te montre **qui bloque qui** — un réflexe RUN essentiel.

### Deadlock — quand deux transactions se bloquent mutuellement

**Scénario classique** : Transaction A verrouille la table `Contrats` puis attend `Clients`. Transaction B verrouille `Clients` puis attend `Contrats`. **Aucune des deux ne peut jamais continuer** — un blocage circulaire.

SQL Server **détecte automatiquement** cette situation et tue une des deux transactions (la "deadlock victim", généralement celle qui coûterait le moins cher à annuler), avec l'erreur 1205.

**Prévention** : **toujours accéder aux tables dans le même ordre** dans tout ton code (convention d'équipe — par exemple toujours `Clients` avant `Contrats`), garder les transactions **courtes**, éviter les transactions qui attendent une interaction utilisateur au milieu.

### Le piège NOLOCK — à ne jamais utiliser en prod financière

```sql
SELECT * FROM FactMouvements WITH (NOLOCK) WHERE ContratKey = 42;
```
**Ce que ça fait** : lit les données **sans poser ni respecter aucun verrou** — équivalent au niveau `READ UNCOMMITTED`. Tu peux lire des données **en cours de modification, potentiellement annulées ensuite (dirty read)**, ou même **sauter/dupliquer des lignes** dans certains cas de réorganisation de page concurrente.

**Pourquoi c'est tentant** : ça évite d'être bloqué par d'autres transactions, donc ça "semble" plus rapide.

**Pourquoi c'est dangereux dans ton contexte assurance vie** : si tu extrais des mouvements financiers avec `NOLOCK` pendant qu'une transaction est en cours d'écriture, tu peux **rapporter un montant qui n'a jamais vraiment existé** (annulé ensuite par un rollback que tu n'as pas vu) — catastrophique pour un rapport réglementaire LCB-FT.

**Alternative recommandée** : `READ COMMITTED SNAPSHOT` (RCSI, déjà vu ensemble) — donne une lecture cohérente sans bloquer les écrivains, **sans le risque de données fantômes** du NOLOCK.

### Exercice 15.1

Deux jobs tournent en même temps chaque nuit : l'un met à jour `Contrats` puis `Clients`, l'autre met à jour `Clients` puis `Contrats`. Un deadlock survient une nuit sur trois. Quelle est la cause, et quelle correction proposes-tu ?

<details>
<summary>Corrigé</summary>

**Cause** : les deux jobs accèdent aux mêmes deux tables **dans un ordre inversé** — c'est le scénario classique de deadlock circulaire décrit plus haut.

**Correction** : harmoniser l'ordre d'accès aux tables dans les deux jobs (par convention d'équipe, toujours `Clients` avant `Contrats`, ou l'inverse — l'important est la cohérence). Alternative si l'ordre ne peut pas être changé pour des raisons métier : réduire la portée/durée des transactions pour minimiser la fenêtre de risque, ou envisager `SET DEADLOCK_PRIORITY` pour désigner explicitement quelle transaction doit céder en cas de conflit plutôt que de laisser SQL Server choisir arbitrairement.
</details>

---

# PARTIE 6 — MISE EN PRATIQUE

## Chapitre 16 — Méthodologie pour écrire une bonne requête

### La check-list mentale à appliquer systématiquement

Avant d'écrire une requête complexe, pose-toi ces questions dans l'ordre :

1. **Quel est le résultat final voulu ?** (une ligne par contrat ? par client ? un total global ?) — ça détermine ton `GROUP BY` ou l'absence de regroupement.
2. **Quelles tables sont nécessaires, et comment se relient-elles ?** — dessine mentalement (ou sur papier) le schéma des jointures avant d'écrire le SQL.
3. **Ai-je besoin de TOUTES les lignes des deux côtés, ou seulement les correspondances ?** — détermine `INNER` vs `LEFT/RIGHT/FULL JOIN`.
4. **Est-ce que je filtre avant ou après agrégation ?** — détermine `WHERE` vs `HAVING`.
5. **Ai-je besoin de garder le détail ligne à ligne, ou de le condenser ?** — détermine `GROUP BY` (condense) vs Window Function (garde le détail).
6. **Cette requête sera-t-elle exécutée souvent, sur un gros volume ?** — si oui, anticipe les besoins d'index dès la conception, pas après coup.
7. **Que se passe-t-il avec les valeurs NULL ?** — teste mentalement chaque colonne : peut-elle être NULL, et si oui, l'agrégat/la comparaison se comporte-t-elle comme prévu ?

### La démarche de diagnostic quand une requête est lente

1. `SET STATISTICS IO, TIME ON` — obtenir des chiffres objectifs.
2. Regarder le plan d'exécution — identifier l'opérateur au plus gros pourcentage de coût.
3. Est-ce un Scan qui devrait être un Seek ? → manque probablement un index.
4. Est-ce un Sort coûteux ? → un index dans le bon ordre pourrait l'éviter.
5. Est-ce un écart estimé/réel énorme ? → suspecter statistiques obsolètes ou paramètre sniffing.
6. Est-ce une fonction scalaire dans le SELECT sur beaucoup de lignes ? → envisager de l'inline ou la remplacer par une iTVF.
7. Documenter ce que tu as changé et pourquoi — pour toi-même et pour l'équipe (rappel de ta base de connaissance de mission).

---

## Chapitre 17 — Exercices de synthèse

### Exercice de synthèse A — Requête complète

Écris une requête qui donne, **pour chaque client actif**, son nombre de contrats actifs, son encours total, et son rang parmi tous les clients selon cet encours (le plus gros encours = rang 1).

<details>
<summary>Corrigé</summary>

```sql
;WITH EncoursParClient AS (
    SELECT
        dcl.NomComplet,
        COUNT(DISTINCT dc.ContratKey) AS NbContrats,
        SUM(f.MontantSigne) AS EncoursTotal
    FROM DimClient dcl
    JOIN DimContrat dc ON dc.ClientId = dcl.ClientId
    LEFT JOIN FactMouvements f ON f.ContratKey = dc.ContratKey
    WHERE dcl.EstCourant = 1 AND dc.Statut = 'Actif'
    GROUP BY dcl.NomComplet
)
SELECT
    NomComplet,
    NbContrats,
    EncoursTotal,
    RANK() OVER (ORDER BY EncoursTotal DESC) AS Rang
FROM EncoursParClient
ORDER BY Rang;
```
**Points clés à vérifier dans ta propre réponse** : `LEFT JOIN` vers `FactMouvements` (un contrat actif peut n'avoir aucun mouvement encore), `EstCourant = 1` pour ne prendre que la version SCD2 actuelle du client, `RANK()` plutôt que `ROW_NUMBER()` si tu veux que des encours identiques partagent le même rang.
</details>

### Exercice de synthèse B — Procédure complète avec gestion d'erreur

Écris une procédure `usp_SoldeClient` qui prend un `@ClientId` en paramètre, retourne le solde total en `OUTPUT`, et lève une erreur explicite si le client n'existe pas.

<details>
<summary>Corrigé</summary>

```sql
CREATE OR ALTER PROCEDURE dbo.usp_SoldeClient
    @ClientId INT,
    @Solde DECIMAL(19,4) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM DimClient WHERE ClientId = @ClientId AND EstCourant = 1)
    BEGIN
        THROW 50001, 'Client introuvable ou inactif.', 1;
    END

    SELECT @Solde = COALESCE(SUM(f.MontantSigne), 0)
    FROM FactMouvements f
    JOIN DimContrat dc ON dc.ContratKey = f.ContratKey
    WHERE dc.ClientId = @ClientId;
END
```
</details>

### Exercice de synthèse C — Diagnostic de performance

Une requête sur `FactMouvements` (5 millions de lignes) prend 12 secondes :
```sql
SELECT * FROM FactMouvements WHERE YEAR(DateOperation) = 2026;
```
Explique pourquoi c'est lent, et corrige.

<details>
<summary>Corrigé</summary>

**Le problème** : `YEAR(DateOperation) = 2026` applique une **fonction sur la colonne indexée**. Même si un index existe sur `DateOperation`, SQL Server **ne peut pas l'utiliser efficacement** — il doit calculer `YEAR(...)` pour **chaque ligne** avant de pouvoir comparer, ce qui empêche un Index Seek et force un Scan complet. C'est ce qu'on appelle une colonne **"non-SARGable"** (non éligible à une recherche par index).

**Correction — réécrire sans fonction sur la colonne** :
```sql
SELECT * FROM FactMouvements
WHERE DateOperation >= '2026-01-01' AND DateOperation < '2027-01-01';
```
Ici, `DateOperation` reste "nue" dans la comparaison — si un index existe dessus, SQL Server peut faire un `Index Seek` direct sur la plage, radicalement plus rapide.

**Règle générale à retenir** : **ne jamais appliquer de fonction sur la colonne dans un WHERE si tu veux qu'un index soit utilisé** — transforme plutôt la comparaison pour que la colonne reste "nue" (comme ici, transformer un filtre sur l'année en une plage de dates).
</details>

---

## Chapitre 18 — Cheat sheet finale

### Choix de structure de données temporaire
- Une seule utilisation, petite requête → **CTE**
- Récursivité (hiérarchie) → **CTE récursive**
- Gros volume, réutilisé, besoin d'index → **Table temporaire `#temp`**
- Petit volume, logique procédurale → **Variable table `@table`**

### Choix de jointure
- Je veux seulement les correspondances → **INNER JOIN**
- Je veux tout de gauche + correspondances (et détecter les manquants) → **LEFT JOIN + IS NULL**
- Je veux comparer deux sources dans les deux sens → **FULL JOIN**
- Je veux toutes les combinaisons possibles → **CROSS JOIN** (rare, volontaire)
- Fonction/sous-requête paramétrée par ligne → **CROSS/OUTER APPLY**

### Choix de fonction
- Logique simple réutilisée, table en retour → **Inline TVF**
- Logique complexe multi-étapes, table en retour → **Procédure stockée** (évite Multi-Statement TVF si possible)
- Valeur unique, appelée peu souvent → **Fonction scalaire** (avec prudence sur gros volumes)

### Diagnostic performance — dans l'ordre
1. `SET STATISTICS IO, TIME ON`
2. Plan d'exécution — repérer le plus gros %
3. Scan au lieu de Seek → index manquant ou colonne non-SARGable (fonction sur colonne)
4. Écart estimé/réel → statistiques obsolètes ou paramètre sniffing
5. Beaucoup de Key Lookup → envisager un index couvrant (`INCLUDE`)

### Les 5 pièges classiques à ne jamais refaire
1. `WHERE colonne = NULL` → utiliser `IS NULL`
2. `NOT IN` avec sous-requête pouvant contenir NULL → utiliser `NOT EXISTS`
3. Fonction sur une colonne indexée dans le WHERE → réécrire en plage/comparaison directe
4. Curseur pour une opération transformable en set-based → toujours chercher l'équivalent ensembliste
5. `NOLOCK` sur des données financières → utiliser RCSI si besoin de non-blocage

### Vocabulaire à ressortir naturellement en mission
« Partition elimination », « covering index », « paramètre sniffing », « SARGable », « plan estimé vs réel », « logical reads », « SWITCH PARTITION », « RCSI ».

---

**Fin de la formation.**

Tu es parti d'un rappel des bases pour arriver au partitionnement de table avec SWITCH PARTITION — le chemin complet d'un développeur SQL Server confirmé. Relis cette formation par petits blocs, refais les exercices sans regarder les corrigés d'abord, et surtout : **applique chaque nouveau concept sur ton labo SEEDVIE** dès que tu peux — c'est la pratique répétée, pas la lecture seule, qui transforme ça en réflexe.

La prochaine fois que ton collègue reparle de partitionnement disque, tu sauras exactement de quoi il parle — et tu pourras même lui demander intelligemment : « c'est du partitionnement de table avec SWITCH pour l'archivage, ou plutôt une répartition de filegroups sur plusieurs disques physiques ? » — la question d'un développeur qui a fait ses devoirs.
