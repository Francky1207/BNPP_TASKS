# INVESTIGATION TOOLKIT — PHASE 3 : PLAYBOOKS COMPLETS
## Procédures d'investigation bout-en-bout par type d'incident

**Version** : 1.0 — Calibré SQL Server 2019, Environnement TFT/IC, RCSI=OFF, Query Store=OFF
**Principe** : Chaque playbook suit le schéma PROBLÈME → SCRIPT → OBSERVATION → DÉCISION → ACTION

---

## LISTE DES PLAYBOOKS

| N° | Incident | Script de départ |
|---|---|---|
| PB-01 | Traitement DATA STUDIO qui ne se termine pas | SQL_DI_04 |
| PB-02 | Script SQL bloqué depuis plusieurs heures (cas du 28/08/2026) | SQL_DI_05 |
| PB-03 | Perte de données entre couches ETL (TFT→ODS→IC) | SQL_ET_01 |
| PB-04 | Job SQL Server Agent en échec | SQL_JA_01 |
| PB-05 | Lenteur générale — serveur qui rame | SQL_DI_01 |
| PB-06 | Disque ou mémoire qui se remplit | PS_FS_01 |
| PB-07 | Données suspectes — doublons, NULL, incohérences | SQL_QD_01 |
| PB-08 | Requête spécifique lente — optimisation ciblée | SQL_PQ_04 |

---

---

# PLAYBOOK PB-01
## Traitement DATA STUDIO qui ne se termine pas

```
SYMPTÔME : Un traitement DATA STUDIO tourne depuis trop longtemps.
            Aucun message d'erreur visible dans les logs.
            Personne ne sait si c'est bloqué ou si ça avance encore.
```

---

### ÉTAPE 1 — Confirmer que quelque chose tourne encore
**Script** : `SQL_DI_04_Find_Long_Running_Queries_RO.sql`
**Paramètres** : `@MinDureeMinutes = 30`

**Observations à faire** :

| Ce que tu vois | Interprétation | Étape suivante |
|---|---|---|
| Aucune ligne retournée | Le traitement est terminé (ou n'a jamais démarré) | → Vérifier les logs DATA STUDIO (PS_LC_01) et le job (SQL_JA_02) |
| Lignes avec `Statut = 'suspended'`, `BloquePar > 0` | Le traitement est **BLOQUÉ** par une autre session | → Étape 2A (Blocking) |
| Lignes avec `Statut = 'running'`, `LogReads` très élevés | Le traitement **tourne** mais fait un scan massif | → Étape 2B (Performance) |
| Lignes avec `CPU(s)` qui n'augmente pas, `Attente = PAGEIOLATCH` | Le disque est saturé | → PB-06 |

---

### ÉTAPE 2A — Le traitement est bloqué
**Script** : `SQL_BL_01_Analyze_Current_Blocking_RO.sql`

**Observations** :

| Ce que tu vois | Signification |
|---|---|
| Session DATA STUDIO bloquée par une session interactive (SSMS, Excel) | Quelqu'un fait une requête sur la même table au même moment |
| Session bloquée par elle-même (deadlock) | Très rare, SQL Server devrait l'avoir tué automatiquement |
| `wait_type = LCK_M_S` | Le BLOQUEUR fait une écriture (INSERT/UPDATE), le bloqué fait une lecture — **aggravé par RCSI désactivé** |
| `wait_type = LCK_M_X` | Le BLOQUEUR fait une écriture longue, bloque toute lecture |

**Action** :
1. Identifier la session bloquante (colonne `Bloqueur`)
2. Lire son SQL (`SQL_SR_04` avec le session_id du bloqueur)
3. Décider : tuer la session bloquante (`KILL [session_id]`) ou attendre

**Point d'attention ⚠️** : Si le bloqueur est une session utilisateur (SELECT depuis Excel ou SSMS), c'est le signe que RCSI devrait être activé. Un SELECT bloquant un INSERT ne devrait pas arriver avec RCSI=ON.

---

### ÉTAPE 2B — Le traitement tourne mais est lent
**Script** : `SQL_PQ_04_Analyze_Query_With_Stats_RO.sql`
Coller le texte SQL (récupéré à l'étape 1, colonne `SQL complet`) dans la section mesure.

**Observations clés (onglet Messages)** :

| Ce que tu vois dans STATISTICS IO | Signification |
|---|---|
| `Scan count 1, logical reads < 100 000` | Requête acceptable |
| `Scan count 1, logical reads > 1 000 000` | Scan massif — index manquant probable |
| `Scan count > 1` sur la même table | **O(n²) — boucle problématique (comme le NOT IN du 28/08)** |

**Si Scan count > 1 → Étape 3 (Index)**

---

### ÉTAPE 3 — Investiguer les index
**Script** : `SQL_IX_01_Find_Missing_Indexes_RO.sql`
**Paramètre** : `@BaseCible = 'IC'`

**Puis** : `SQL_IX_02_List_Table_Indexes_RO.sql`
Sur la table identifiée à l'étape 2.

**Décision** :

| Observation | Action |
|---|---|
| Index manquant suggéré avec impact > 80% sur la table concernée | Créer l'index (en RECETTE d'abord, puis PROD) |
| L'index existe mais n'est pas utilisé | Vérifier si la requête a une fonction sur la colonne (non-SARGable) ou un `NOT IN` |
| Aucun index manquant suggéré mais Scan count > 1 | Le problème est la structure de la requête (NOT IN, sous-requête corrélée) |

**Si le problème est un NOT IN → remplacer par LEFT JOIN (voir SQL_ET_05)**

---

### ÉTAPE 4 — Décider : tuer ou laisser terminer

**Calculer une estimation de durée restante** :
```sql
-- Dans l'onglet Live Query Statistics de SSMS (si activé)
-- ou via :
SELECT
    session_id,
    total_elapsed_time / 1000 AS [Durée passée (s)],
    logical_reads AS [Lectures faites],
    estimated_completion_time / 1000 AS [Temps restant estimé (s)] -- disponible pour BACKUP/DBCC
FROM sys.dm_exec_requests
WHERE session_id = [session_id_du_traitement];
```

**Règle de décision** :
- Si le traitement avance (logical_reads augmente) et que le temps restant est acceptable → **laisser tourner**
- Si le traitement est bloqué (CPU = 0, BloquePar > 0) → **tuer le bloqueur** (avec accord)
- Si le traitement est O(n²) et que ça fait déjà 10h+ → **tuer et corriger le script** avant de relancer

---

### ÉTAPE 5 — Après résolution
1. Vérifier les volumes : `SQL_ET_01_Compare_RowCounts_All_Layers_RO.sql`
2. Vérifier les rejets / données partielles : `SQL_QD_01_Find_Duplicates_In_Table_RO.sql`
3. Documenter dans ta base de connaissance :
   - Quelle table était concernée
   - Quelle était la cause (blocking / O(n²) / index manquant)
   - Quelle action a résolu
   - Quelle durée normale vs durée observée

---
---

# PLAYBOOK PB-02
## Script SQL bloqué depuis plusieurs heures
## (Cas concret du 28/08/2026 — NOT IN sur ODS_MOUVEMENTS_PERE)

```
SYMPTÔME : Un script SQL a été lancé manuellement ou via un job.
            Plusieurs heures plus tard, il n'est toujours pas terminé.
            Pas d'erreur visible. La question est : tourne-t-il encore
            ou est-il bloqué ? Et si ça tourne, pourquoi c'est si lent ?
```

---

### ÉTAPE 1 — Le script est-il encore en vie ?
**Script** : `SQL_DI_04_Find_Long_Running_Queries_RO.sql`
**Paramètres** : `@MinDureeMinutes = 60`

**Résultat attendu** :
```
SessionId | Login | Base | Durée(s) | CPU(s) | LogReads | BloquePar | Signal
----------+-------+------+----------+--------+----------+-----------+-------
87        | LOGIN | IC   | 72000    | 45000  | 3E+09    | 0         | SCAN MASSIF
```

**Interprétation de ce cas** :
- `Durée = 72 000s` = 20 heures → anormal
- `CPU(s)` qui augmente → le script **tourne** (pas bloqué par un verrou)
- `LogReads = 3 milliards` → scan **massivement répété** = O(n²) confirmé
- `BloquePar = 0` → pas de blocking externe

---

### ÉTAPE 2 — Lire le SQL exact du script qui tourne
**Script** : `SQL_SR_04_Get_Query_Text_From_Session_RO.sql`
**Paramètre** : `@SessionId = 87` (session identifiée à l'étape 1)

**Ce que tu vas probablement voir** :
```sql
WHILE (@L_RESTE = @L_PAQUET)
BEGIN
    INSERT INTO ODS_MOUVEMENTS_PERE (...)
    SELECT TOP (100000) ...
    FROM TFT.dbo.TFT_K_POLICY_OPERATIONS SOURCE
    WHERE SOURCE.POL_OPERATION_ID NOT IN (
        SELECT N_MOUVEMENT FROM ODS_MOUVEMENTS_PERE   -- ← LE PROBLÈME
    )
    ...
    SELECT @L_RESTE = @@ROWCOUNT;
END
```

**Diagnostic** : `NOT IN (SELECT ... FROM table_qui_grossit)` dans une boucle WHILE = **O(n²) classique**

---

### ÉTAPE 3 — Confirmer le O(n²) avec les statistiques
**Script** : `SQL_PQ_04_Analyze_Query_With_Stats_RO.sql`
Coller le SELECT intérieur (sans le WHILE) dans la section mesure.

**Ce que tu vas voir dans l'onglet Messages** :
```
Table 'ODS_MOUVEMENTS_PERE'. Scan count 1, logical reads 184 000 000
```
`Scan count 1` pour cette exécution unique — mais multiplié par le nombre d'itérations de la boucle,
ça fait des **milliards** de lectures au total. C'est confirmé.

**Et dans le plan d'exécution** : `Clustered Index Scan` à 100% du coût
→ Comme visible sur la capture d'écran du 28/08 : `Estimated Operator Cost: 184.62 (100%)`

---

### ÉTAPE 4 — Décision : tuer ou laisser terminer

**Calculer combien d'itérations ont été faites** :
```sql
-- Combien de lignes sont dans ODS_MOUVEMENTS_PERE maintenant ?
SELECT SUM(row_count) AS [Lignes insérées jusqu'ici]
FROM IC.sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID('IC.dbo.ODS_MOUVEMENTS_PERE')
  AND index_id IN (0,1);

-- Combien en reste-t-il à insérer ?
SELECT COUNT(*) AS [Lignes source non encore insérées]
FROM TFT.dbo.TFT_K_POLICY_OPERATIONS src
INNER JOIN IC.dbo.ODS_CONTRATS_DAV CTR
    ON CTR.REFERENCE_EXTERNE_KELIA = src.POLICY_ID AND CTR.SOURCE = 2 AND src.ARCHIVED <> 2
LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp ON omp.N_MOUVEMENT = src.POL_OPERATION_ID
WHERE omp.N_MOUVEMENT IS NULL;
-- ⚠️ Cette requête elle-même peut être longue — la variante O(n) ci-dessus
```

**Règle** :
- Si 95% inséré et chaque itération prend 30 min → peut-être vaut le coup d'attendre
- Si 30% inséré et chaque itération prend 1h de plus que la précédente (O(n²) aggravé) → **tuer**

**Action si on tue** :
```sql
KILL 87;  -- session_id identifié à l'étape 1
-- Attendre la fin du rollback (quelques minutes selon ce qui était dans la transaction)
```

---

### ÉTAPE 5 — Préparer la version corrigée avant de relancer
**Avant de relancer** : créer l'index manquant

```sql
-- Vérifier s'il existe déjà
SELECT name FROM IC.sys.indexes
WHERE object_id = OBJECT_ID('IC.dbo.ODS_MOUVEMENTS_PERE')
  AND name LIKE '%N_MOUVEMENT%';

-- S'il n'existe pas, le créer (ONLINE = pas de blocage en production)
CREATE NONCLUSTERED INDEX [IX_ODS_MOUVEMENTS_PERE_N_MOUVEMENT]
ON IC.dbo.ODS_MOUVEMENTS_PERE (N_MOUVEMENT)
WITH (ONLINE = ON);
```

**Script corrigé** (voir `SQL_ET_05_Find_Orphan_Records_RO.sql` pour le code complet) :
```sql
-- Remplacer le NOT IN par LEFT JOIN
WHILE 1 = 1
BEGIN
    INSERT INTO IC.dbo.ODS_MOUVEMENTS_PERE (ID_CONTRAT, N_MOUVEMENT, N_MOUVEMENT_PERE, POL_QUEUE_ID)
    SELECT TOP (100000)
        CAST(CTR.ID_CONTRAT AS INT),
        CAST(src.POL_OPERATION_ID AS INT),
        CAST(CASE WHEN src.POL_OPERATION_PID = 0 THEN NULL ELSE src.POL_OPERATION_PID END AS INT),
        CAST(src.POL_QUEUE_ID AS INT)
    FROM TFT.dbo.TFT_K_POLICY_OPERATIONS src
    INNER JOIN IC.dbo.ODS_CONTRATS_DAV CTR
        ON CTR.REFERENCE_EXTERNE_KELIA = src.POLICY_ID
        AND CTR.SOURCE = 2 AND src.ARCHIVED <> 2
    LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp     -- ← LEFT JOIN
        ON omp.N_MOUVEMENT = src.POL_OPERATION_ID
    WHERE omp.N_MOUVEMENT IS NULL;               -- ← IS NULL

    IF @@ROWCOUNT < 100000 BREAK;                -- ← condition correcte (< pas =)
END;
```

---

### ÉTAPE 6 — Mesurer l'amélioration (preuve objective)
**Script** : `SQL_CM_01_Benchmark_Before_After_RO.sql`

Insérer les deux versions (NOT IN et LEFT JOIN) dans les sections Mesure 1 et Mesure 2.
Comparer :
- `Scan count` (doit passer de N à 1)
- `Logical reads` (doit baisser de 95%+)
- `Durée en ms` (doit passer de heures à minutes)

---
---

# PLAYBOOK PB-03
## Perte de données entre couches ETL (TFT→ODS→IC)

```
SYMPTÔME : Un utilisateur métier signale que des données manquent
            dans les tableaux de bord ou extractions.
            Ou tu constates toi-même un écart entre les volumes attendus.
```

---

### ÉTAPE 1 — Localiser la perte dans la chaîne
**Script** : `SQL_ET_01_Compare_RowCounts_All_Layers_RO.sql`

**Schéma de lecture** :
```
TFT : 1 200 000 lignes  ← volume source (fichiers CRE)
ODS : 1 180 000 lignes  ← légère perte, peut être normale (filtres métier)
IC  :    50 000 lignes  ← PERTE MASSIVE ici → le problème est ODS→IC
```

**Cas possibles** :

| Situation | Signification |
|---|---|
| TFT = 0 | Le fichier CRE n'a pas été chargé → PS_ET_01 (vérifier fichiers) |
| TFT OK, ODS = 0 | Le traitement DATA STUDIO TFT→ODS n'a pas tourné → SQL_JA_01 |
| ODS OK, IC << ODS | Perte entre ODS et IC → Étape 2 |
| IC OK mais données fausses | Pas une perte de lignes, problème de qualité → PB-07 |

---

### ÉTAPE 2 — Identifier les lignes orphelines
**Script** : `SQL_ET_05_Find_Orphan_Records_RO.sql`
**Paramètres** : `@ModeEstimation = 1` (compter d'abord)

**Résultat** :
```
Paire analysée                    | Nb lignes orphelines | Diagnostic
ODS_MOUVEMENTS → IC_MOUVEMENTS    | 142 853              | PERTES SIGNIFICATIVES
```

Puis `@ModeEstimation = 0` pour voir un échantillon des lignes orphelines.

---

### ÉTAPE 3 — Comprendre pourquoi ces lignes ne sont pas passées
**Analyser les lignes orphelines** :
```sql
-- Prendre un échantillon des ODS non passés en IC
-- et comparer avec les règles de filtrage du script DATA STUDIO
SELECT TOP 100
    omp.N_MOUVEMENT,
    omp.ID_CONTRAT,
    omp.N_MOUVEMENT_PERE,
    -- Ajouter ici les colonnes qui pourraient être à l'origine du filtre
    -- (statut, type, date, code produit...)
FROM IC.dbo.ODS_MOUVEMENTS_PERE omp
LEFT JOIN IC.dbo.IC_MOUVEMENTS im ON im.N_MOUVEMENT = omp.N_MOUVEMENT  -- adapter selon la vraie table IC
WHERE im.N_MOUVEMENT IS NULL;  -- ceux qui ne sont pas en IC
```

**Causes fréquentes de perte ODS→IC** :
1. **Filtre trop restrictif** dans le script DATA STUDIO (condition sur un statut, une date, un type)
2. **Jointure qui exclut des lignes** (INNER JOIN sur une table de référence incomplète)
3. **Contrainte violated en base IC** (FK, CHECK, UNIQUE) → des INSERT ont échoué silencieusement
4. **Traitement incomplet** — le job a planté en cours de route et a inséré seulement une partie

---

### ÉTAPE 4 — Vérifier si le traitement IC s'est exécuté complètement
**Script** : `SQL_JA_02_Get_Job_History_RO.sql`
**Paramètre** : nom du job qui fait le chargement ODS→IC

**Et vérifier les logs DATA STUDIO** :
**Script** : `PS_LC_01_Parse_DataStudio_Logs_RO.ps1`
Chercher dans les logs si le traitement a une ligne de début sans ligne de fin (plantage en cours de route).

---

### ÉTAPE 5 — Vérifier la qualité des données ODS (avant IC)
**Script** : `SQL_QD_01_Find_Duplicates_In_Table_RO.sql` sur la table ODS concernée
**Script** : `SQL_QD_02_Check_Null_Coverage_RO.sql` sur les colonnes clés

Des NULL non attendus ou des doublons dans l'ODS peuvent provoquer des rejets silencieux lors du chargement IC.

---

### ÉTAPE 6 — Action corrective et vérification

Selon la cause identifiée :
- **Filtre trop restrictif** → corriger le script DATA STUDIO, relancer le traitement ODS→IC
- **Jointure manquante** → ajouter les données manquantes dans la table de référence et relancer
- **Traitement incomplet** → rejouer le traitement complet
- **Contrainte SQL** → corriger les données ODS, puis rejouer

**Vérification finale** : `SQL_ET_01` → les volumes TFT/ODS/IC doivent être cohérents.

---
---

# PLAYBOOK PB-04
## Job SQL Server Agent en échec

```
SYMPTÔME : Le contrôle RUN du matin révèle qu'un job a échoué.
            Ou une alerte SQL Agent a été envoyée par mail.
```

---

### ÉTAPE 1 — Identifier le ou les jobs en échec
**Script** : `SQL_JA_01_List_Failed_Jobs_Last24h_RO.sql`
**Paramètre** : `@HeuresRetroactif = 24`

**Lire les colonnes clés** :
- `Message erreur` → souvent le message SQL Server exact qui a planté
- `Etape` → quelle étape du job a échoué (étape 1, 2, 3...)
- `Durée (secondes)` → comparer avec la durée habituelle (`SQL_JA_02`)

---

### ÉTAPE 2 — Comparer avec l'historique du job
**Script** : `SQL_JA_02_Get_Job_History_RO.sql`

**Observations** :

| Ce que tu vois | Signification |
|---|---|
| Durée habituelle = 3 600s, durée hier = 72 000s, puis échec | Le job a tourné anormalement longtemps avant d'échouer → PB-01 |
| Durée = 0s, échec immédiat | Problème de configuration, droits, connexion base |
| Durée normale mais échec à l'étape 3 | Problème spécifique à cette étape (données, fichier, contrainte) |
| Tendance à la hausse des durées semaine après semaine | Performance dégradée progressive → investiguer index/volume |

---

### ÉTAPE 3 — Analyser le message d'erreur

**Catalogue des messages d'erreur fréquents et leur action** :

| Message d'erreur | Cause probable | Action |
|---|---|---|
| `Cannot open database "IC"` | Base indisponible ou connexion refusée | Vérifier état base (`SQL_DI_06`) |
| `Timeout expired` | Requête trop longue (CommandTimeout) | Optimiser la requête ou augmenter timeout |
| `Violation of PRIMARY KEY constraint` | Doublon inséré | `SQL_QD_01` sur la table cible |
| `Violation of FOREIGN KEY constraint` | Donnée orpheline insérée | Vérifier référentiel source |
| `The transaction log is full` | LDF saturé | `SQL_FS_02` puis libérer espace journal |
| `Login failed` | Compte de service expiré ou révoqué | Vérifier compte SQL Agent |
| `Cannot bulk load because the file ... does not exist` | Fichier CRE manquant | `PS_ET_01` |
| `String or binary data would be truncated` | Donnée trop longue pour la colonne | Inspecter les données sources |

---

### ÉTAPE 4 — Vérifier si d'autres jobs dépendants ont été impactés
```sql
-- Y a-t-il d'autres jobs qui auraient dû tourner après celui qui a échoué ?
-- Vérifier manuellement la chaîne de dépendances dans SQL Server Agent
-- (onglet "Schedules" et "Steps" de chaque job dans SSMS)
EXEC msdb.dbo.sp_help_jobdependency;  -- si dépendances configurées
```

---

### ÉTAPE 5 — Corriger et rejouer

1. Corriger la cause (selon étape 3)
2. Vérifier l'état des données (traitement partiel ?) : `SQL_ET_01`
3. Nettoyer si nécessaire les données partiellement insérées (si idempotent → pas besoin)
4. Relancer le job :
```sql
EXEC msdb.dbo.sp_start_job @job_name = 'Nom du Job';
```
5. Surveiller : `SQL_JA_03_List_Running_Jobs_RO.sql`
6. Vérifier le résultat : `SQL_JA_01` + `SQL_ET_01`

---
---

# PLAYBOOK PB-05
## Lenteur générale — le serveur qui rame

```
SYMPTÔME : Tout est lent. Les traitements DATA STUDIO durent le double.
            SSMS répond lentement. Les utilisateurs se plaignent.
            Il n'y a pas d'incident identifiable, juste une lenteur globale.
```

---

### ÉTAPE 1 — Snapshot global immédiat (parallèle SQL + Windows)

**Ouvrir DEUX sessions simultanément** :

Session 1 (SSMS) : `SQL_DI_01_Get_Server_Health_RO.sql`
Session 2 (PowerShell sur le serveur) : `PS_WS_01_Get_Server_Resources_Snapshot_RO.ps1`

**Croiser les résultats** :

| SQL_DI_01 dit | PS_WS_01 dit | Conclusion |
|---|---|---|
| CPU wait_type=CXPACKET | CPU Windows normal | Parallélisme excessif SQL — vérifier MAXDOP |
| Peu d'attentes SQL | CPU Windows 95% | Un autre processus consomme le CPU (PS_WS_03) |
| PAGEIOLATCH dominant | I/O disque élevé | Disque saturé — SQL_MC_03 |
| RESOURCE_SEMAPHORE | RAM SQL 90%+ | Pression mémoire — SQL_MC_01 |
| LCK_* dominant | Charge Windows normale | Blocking — SQL_BL_01 |

---

### ÉTAPE 2 — Creuser selon l'indicateur principal

**Si CPU** → `SQL_MC_02_Check_CPU_Usage_RO.sql` + `SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql`

**Si I/O** → `SQL_MC_03_Analyze_IO_By_Database_RO.sql`
```
Quelle base génère le plus d'I/O ?
→ Sur cette base : SQL_OB_03 (tables volumineuses) + SQL_IX_04 (fragmentation)
```

**Si Mémoire** → `SQL_MC_01_Check_Memory_Pressure_RO.sql`
```
SQL Server utilise-t-il toute la RAM allouée ?
→ Si oui et serveur dégradé : augmenter max server memory (DBA)
→ Si requêtes avec memory grant en attente (queue_id non null) → optimiser les tris/hash joins
```

**Si Blocking** → directement `SQL_BL_01_Analyze_Current_Blocking_RO.sql` → PB-02

---

### ÉTAPE 3 — Vérifier si tempdb est saturée

**Souvent négligée mais cause fréquente de lenteur globale** :
**Script** : `SQL_MC_04_Check_Tempdb_Usage_RO.sql`

Si une session consomme massivement tempdb (tris, hash joins, tables temporaires) → elle ralentit **tout le monde**

---

### ÉTAPE 4 — Vérifier les jobs en cours simultanément

```sql
-- Y a-t-il plusieurs gros jobs qui tournent en même temps ?
-- (charge cumulée qui dépasse la capacité du serveur)
SELECT * FROM msdb.dbo.sysjobactivity
WHERE start_execution_date IS NOT NULL
  AND stop_execution_date IS NULL;
```

Parfois la lenteur vient simplement de **deux gros traitements ETL qui tournent en parallèle** alors qu'ils devraient être séquentiels.

---
---

# PLAYBOOK PB-06
## Disque ou mémoire qui se remplit

```
SYMPTÔME : Alerte espace disque. Ou un traitement échoue avec
            "The transaction log is full" ou "insufficient disk space".
```

---

### ÉTAPE 1 — État des disques
**Script** : `PS_FS_01_Check_Disk_Space_All_Drives_RO.ps1`
**Script** : `SQL_FS_01_Analyze_Database_Files_RO.sql`

**Identifier quel fichier remplit quel disque** :
- Si c'est un `.ldf` (journal) qui croît → `SQL_FS_02_Check_Log_File_Usage_RO.sql`
- Si c'est un `.mdf`/`.ndf` (données) → données qui grossissent → vérifier volumétrie ETL

---

### ÉTAPE 2 — Cas fréquent : fichier journal qui explose

**Script** : `SQL_FS_02_Check_Log_File_Usage_RO.sql`

| `log_reuse_wait_desc` | Cause | Action |
|---|---|---|
| `LOG_BACKUP` | Pas de sauvegarde de journal planifiée | Demander au DBA de configurer les sauvegardes de journal |
| `ACTIVE_TRANSACTION` | Transaction longue ouverte | `SQL_SR_04` puis identifier et gérer la transaction |
| `NOTHING` | Journal peut être réutilisé, problème ailleurs | Vérifier si la croissance auto est trop petite |

**Action d'urgence si le journal est trop gros** (à valider avec le DBA) :
```sql
-- Forcer un checkpoint pour marquer les transactions inactives
CHECKPOINT;

-- Puis sauvegarder le journal (en mode FULL)
BACKUP LOG [NomBase] TO DISK = 'NUL';  -- ⚠️ seulement pour libérer l'espace, pas pour la vraie sauvegarde

-- Puis réduire le fichier journal (temporairement, pas une bonne pratique long terme)
DBCC SHRINKFILE ([NomFichierLogique_Log], 1024);  -- réduire à 1 Go
```

---

### ÉTAPE 3 — Identifier les plus gros consommateurs d'espace

**Scripts** : `SQL_OB_03_List_All_Tables_With_Sizes_RO.sql` sur la base concernée

**Et vérifier les gros fichiers Windows** :
**Script** : `PS_FS_02_Find_Large_Files_In_Directory_RO.ps1` sur les répertoires CRE et logs DATA STUDIO

**Les logs DATA STUDIO s'accumulent-ils ?** Si les fichiers `.log`/`.txt` ne sont pas purgés régulièrement, ils peuvent saturer le disque sur lequel ils sont écrits.

---
---

# PLAYBOOK PB-07
## Données suspectes — doublons, NULL, incohérences

```
SYMPTÔME : Un utilisateur métier signale des chiffres étranges.
            Des agrégats qui ne correspondent pas.
            Des enregistrements en double dans les rapports.
```

---

### ÉTAPE 1 — Confirmer les doublons
**Script** : `SQL_QD_01_Find_Duplicates_In_Table_RO.sql`
Sur la table signalée par l'utilisateur.

**Si doublons confirmés** : identifier à quelle étape ils ont été introduits.

---

### ÉTAPE 2 — Remonter la chaîne
```sql
-- Les doublons sont-ils déjà dans la couche source ?
-- Vérifier la table TFT correspondante avec le même script
-- Si TFT a des doublons → problème dans le fichier CRE source
-- Si TFT est propre mais ODS a des doublons → problème dans le traitement TFT→ODS
-- Si ODS est propre mais IC a des doublons → problème dans le traitement ODS→IC
```

---

### ÉTAPE 3 — Analyser la qualité globale
**Script** : `SQL_QD_02_Check_Null_Coverage_RO.sql` sur les tables ODS et IC

Des colonnes qui devraient être renseignées mais qui sont à NULL révèlent souvent une jointure manquante ou un fichier source incomplet.

---

### ÉTAPE 4 — Vérifier si les doublons viennent d'un rejeu

Si un traitement a été relancé après un incident sans vider la table cible au préalable, et que le script d'insertion n'est pas idempotent (pas de vérification d'existence), il peut insérer deux fois les mêmes données.

**Vérification** : regarder l'historique du job (`SQL_JA_02`) — y a-t-il eu deux exécutions proches dans le temps ?

---
---

# PLAYBOOK PB-08
## Requête spécifique lente — optimisation ciblée

```
SYMPTÔME : Une requête précise est identifiée comme lente.
            Tu veux la mesurer, comprendre pourquoi, et prouver l'amélioration.
```

---

### CHECKLIST D'OPTIMISATION D'UNE REQUÊTE

**Étape 1** — Mesurer le coût actuel (baseline)
→ `SQL_CM_01_Benchmark_Before_After_RO.sql` : noter logical reads + durée

**Étape 2** — Lire le plan d'exécution réel
→ Ctrl+M dans SSMS, exécuter la requête, analyser
→ Chercher : Clustered Index Scan (mauvais), Key Lookup (peut être amélioré)

**Étape 3** — Poser les 8 questions diagnostiques

| Question | Comment vérifier | Solution typique |
|---|---|---|
| 1. Y a-t-il un index manquant ? | `SQL_IX_01` + regarder le plan (triangle jaune) | Créer l'index suggéré |
| 2. La colonne est-elle SARGable ? | Chercher `YEAR(col)`, `CAST(col)`, `SUBSTRING(col)` dans le WHERE | Réécrire sans fonction sur la colonne |
| 3. Y a-t-il un NOT IN problématique ? | Chercher `NOT IN (SELECT ...)` | Remplacer par LEFT JOIN + IS NULL |
| 4. Y a-t-il une conversion implicite ? | Plan d'exécution → CONVERT_IMPLICIT | Aligner les types des colonnes comparées |
| 5. Les statistiques sont-elles à jour ? | `SQL_IX_05` sur les tables concernées | `UPDATE STATISTICS` |
| 6. Y a-t-il du paramètre sniffing ? | Comparer plan estimé vs réel (écart de cardinalité) | `OPTION (RECOMPILE)` |
| 7. Y a-t-il un tri coûteux ? | `Sort` dans le plan à % élevé | Index dans l'ordre du ORDER BY |
| 8. Le volume est-il la vraie cause ? | Comparer avec historique (`SQL_PQ_03`) | Partitionnement, archivage, purge |

**Étape 4** — Appliquer la correction

**Étape 5** — Mesurer à nouveau
→ `SQL_CM_01` : comparer avec la baseline
→ `SQL_CM_04` (si index ajouté) : comparer usage index avant/après

**Étape 6** — Documenter la preuve :
```
Avant : logical reads = 45 000 000, durée = 1 800s
Après : logical reads = 12 000, durée = 3s
Gain  : -99.9% lectures, -99.8% durée
Cause : NOT IN remplacé par LEFT JOIN + index créé sur N_MOUVEMENT
```

---
---

# SYNTHÈSE — ARBRE DE DÉCISION GÉNÉRAL

```
PROBLÈME DÉTECTÉ
       │
       ▼
SQL_DI_01 — Vue d'ensemble (30 secondes)
       │
       ├─ Blocking actif ?
       │      └──► SQL_BL_01 → PB-02
       │
       ├─ Requête longue (> 30 min) ?
       │      └──► SQL_DI_04 → PB-01
       │
       ├─ Job en échec ?
       │      └──► SQL_JA_01 → PB-04
       │
       ├─ Waits : PAGEIOLATCH / RESOURCE_SEMAPHORE ?
       │      └──► SQL_MC_03 / SQL_MC_01 → PB-05
       │
       ├─ Données manquantes signalées ?
       │      └──► SQL_ET_01 → PB-03
       │
       ├─ Disque plein ?
       │      └──► PS_FS_01 / SQL_FS_02 → PB-06
       │
       └─ Données suspectes / doublons ?
              └──► SQL_QD_01 → PB-07
```

---

# ROUTINE DE RUN QUOTIDIEN (8h30)

**Séquence recommandée chaque matin** :

```
1. [30s] SQL_JA_01 — Jobs en échec depuis minuit ?
         Si oui → PB-04

2. [30s] SQL_DI_05 — Y a-t-il du blocking actif ?
         Si oui → SQL_BL_01 → PB-02

3. [1min] SQL_DI_04 (@MinDureeMinutes=60) — Requêtes longues en cours ?
          Si oui → PB-01

4. [1min] SQL_ET_01 — Volumes TFT/ODS/IC cohérents ?
          Si tables vides → PS_ET_01 (fichiers CRE)
          Si pertes → PB-03

5. [30s] PS_DI_01 — CPU/RAM/Disque Windows OK ?
         Si alerte → PB-05 ou PB-06

Total : ~4 minutes pour un état complet de la santé du système
```

---

# NOTES D'ADAPTATION

**Sur PS_LC_01 (parser logs DATA STUDIO)** :
Ce script est livré avec des patterns génériques. Pour le calibrer précisément, envoie un extrait de 20-30 lignes réelles de tes logs DATA STUDIO (avec les formats d'heure, de début/fin d'étape, de durée). Je pourrai alors adapter exactement les expressions régulières à ton format réel.

**Sur Query Store (désactivé)** :
La Phase 3 n'inclut pas de playbook Query Store puisqu'il est désactivé sur votre environnement. Si vous l'activez (`ALTER DATABASE IC SET QUERY_STORE = ON`), je peux construire un playbook PB-09 dédié à l'analyse des régressions de plan.

**Sur les scripts P1/P2/P3 restants** :
La Phase 2 a livré tous les scripts P0. Les scripts P1 à P3 (plus spécialisés : Query Store, analyse mémoire avancée, Extended Events, comparaisons complexes) sont disponibles sur demande script par script selon les besoins identifiés en mission.
