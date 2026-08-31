/*
============================================================
NOM          : SQL_ET_01_Compare_RowCounts_All_Layers_RO.sql
CATEGORIE    : 10 - ETL / CHAÎNE DE TRAITEMENT
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré pour chaîne TFT / IC (ODS+IC)
============================================================

OBJECTIF :
  Comparer les volumes de données à chaque étape de la chaîne
  de traitement DATA STUDIO : TFT → ODS → IC.
  Répondre à la question : "Où les lignes ont-elles disparu ?"

  C'est LE script de contrôle quotidien pour valider qu'un
  traitement complet a bien fonctionné.

TYPE        : READ ONLY
RISQUE      : MOYEN sur tables volumineuses (ODS_Mouvements = 45M lignes)
  → Ce script utilise sys.dm_db_partition_stats pour le comptage
    rapide SANS scanner les tables (pas de COUNT(*) sur 45M lignes)

PERMISSIONS : db_datareader, VIEW DATABASE STATE

CONTEXTE SPÉCIFIQUE :
  Base TFT  → Tables de transit CRE (fichiers Excel/CSV)
  Base IC   → Tables ODS_* (staging) et IC_* (tables finales)
  Pas de colonnes de date de chargement dans les tables métier
  → Le comptage de lignes est le principal indicateur disponible

PARAMÈTRES :
  @BaseTFT   — nom de la base TFT (défaut : 'TFT')
  @BaseIC    — nom de la base IC (défaut : 'IC')
  @FiltreTable — filtre sur le nom de table ('' = toutes, 'MOUVEMENT' = tables MOUVEMENT*)

UTILISATION :
  -- Voir toutes les tables des deux bases
  @FiltreTable = ''

  -- Voir seulement les tables liées aux mouvements
  @FiltreTable = 'MOUVEMENT'

RÉSULTATS :
  Partie 1 : Volumes par couche (TFT, ODS, IC) avec tendance
  Partie 2 : Tables avec suspicion de perte (TFT >> ODS ou ODS >> IC)
  Partie 3 : Tables vides ou quasi-vides (signal d'alerte)

INTERPRÉTATION :
  TFT >> ODS   → perte de lignes lors du chargement ODS
  ODS >> IC    → perte de lignes lors du chargement IC
  ODS = 0      → table ODS non chargée — traitement incomplet
  TFT = 0      → fichier CRE non chargé — vérifier fichier source

ETAPE SUIVANTE :
  Si perte détectée → SQL_ET_05_Find_Orphan_Records_RO.sql
  Si table vide     → PS_ET_01_Check_CRE_Files_Status_RO.ps1
  Si TFT = 0        → vérifier les fichiers CRE dans le répertoire
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- PARAMÈTRES
-- ============================================================
DECLARE @BaseTFT      NVARCHAR(128) = 'TFT';
DECLARE @BaseIC       NVARCHAR(128) = 'IC';
DECLARE @FiltreTable  NVARCHAR(128) = '';   -- '' = toutes

PRINT '================================================================';
PRINT 'SQL_ET_01 — COMPARAISON VOLUMES TFT / ODS / IC';
PRINT 'Base TFT  : ' + @BaseTFT;
PRINT 'Base IC   : ' + @BaseIC;
PRINT 'Filtre    : ' + CASE WHEN @FiltreTable = '' THEN '(toutes tables)' ELSE @FiltreTable END;
PRINT 'Horodatage: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';

-- ============================================================
-- PARTIE 1 — VOLUMES PAR COUCHE
-- Utilisation de sys.dm_db_partition_stats → SANS SCAN de table
-- 1000x plus rapide que COUNT(*) sur une table de 45M lignes
-- ============================================================
PRINT '';
PRINT '--- PARTIE 1 : VOLUMES PAR COUCHE ---';

-- Volume tables TFT
SELECT
    'TFT'                               AS [Couche],
    t.name                              AS [Table],
    SUM(ps.row_count)                   AS [Nb lignes],
    SUM(ps.used_page_count * 8) / 1024  AS [Taille Mo],
    CASE
        WHEN SUM(ps.row_count) = 0
        THEN '🔴 VIDE — fichier CRE chargé ?'
        WHEN SUM(ps.row_count) < 1000
        THEN '🟡 Très peu de lignes'
        ELSE '🟢 OK'
    END                                 AS [Statut]
FROM TFT.sys.tables t
JOIN TFT.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id
WHERE ps.index_id IN (0, 1)  -- heap ou clustered index uniquement
  AND (@FiltreTable = '' OR t.name LIKE '%' + @FiltreTable + '%')
GROUP BY t.name
ORDER BY SUM(ps.row_count) DESC;

-- Volume tables ODS (dans la base IC)
SELECT
    'ODS'                               AS [Couche],
    t.name                              AS [Table],
    SUM(ps.row_count)                   AS [Nb lignes],
    SUM(ps.used_page_count * 8) / 1024  AS [Taille Mo],
    CASE
        WHEN SUM(ps.row_count) = 0
        THEN '🔴 VIDE — traitement ODS effectué ?'
        WHEN SUM(ps.row_count) < 1000
        THEN '🟡 Très peu de lignes'
        ELSE '🟢 OK'
    END                                 AS [Statut]
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id
WHERE ps.index_id IN (0, 1)
  AND t.name LIKE 'ODS[_]%'
  AND (@FiltreTable = '' OR t.name LIKE '%' + @FiltreTable + '%')
GROUP BY t.name
ORDER BY SUM(ps.row_count) DESC;

-- Volume tables IC (dans la base IC)
SELECT
    'IC'                                AS [Couche],
    t.name                              AS [Table],
    SUM(ps.row_count)                   AS [Nb lignes],
    SUM(ps.used_page_count * 8) / 1024  AS [Taille Mo],
    CASE
        WHEN SUM(ps.row_count) = 0
        THEN '🔴 VIDE — traitement IC effectué ?'
        WHEN SUM(ps.row_count) < 1000
        THEN '🟡 Très peu de lignes'
        ELSE '🟢 OK'
    END                                 AS [Statut]
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id
WHERE ps.index_id IN (0, 1)
  AND t.name LIKE 'IC[_]%'
  AND (@FiltreTable = '' OR t.name LIKE '%' + @FiltreTable + '%')
GROUP BY t.name
ORDER BY SUM(ps.row_count) DESC;

-- ============================================================
-- PARTIE 2 — VUE SYNTHÉTIQUE PAR PAIRES TFT/ODS
-- Comparer les volumes TFT (source) vs ODS (cible) quand possible
-- ============================================================
PRINT '';
PRINT '--- PARTIE 2 : SYNTHÈSE GLOBALE PAR BASE ---';

SELECT
    'TFT'                                                   AS [Base],
    COUNT(DISTINCT t.name)                                  AS [Nb tables],
    SUM(ps.row_count)                                       AS [Total lignes],
    SUM(ps.used_page_count * 8) / 1024                      AS [Total Mo],
    COUNT(CASE WHEN ps.row_count = 0 THEN 1 END)            AS [Tables vides]
FROM TFT.sys.tables t
JOIN TFT.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)

UNION ALL

SELECT
    'ODS (dans IC)',
    COUNT(DISTINCT t.name),
    SUM(ps.row_count),
    SUM(ps.used_page_count * 8) / 1024,
    COUNT(CASE WHEN ps.row_count = 0 THEN 1 END)
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name LIKE 'ODS[_]%'

UNION ALL

SELECT
    'IC (dans IC)',
    COUNT(DISTINCT t.name),
    SUM(ps.row_count),
    SUM(ps.used_page_count * 8) / 1024,
    COUNT(CASE WHEN ps.row_count = 0 THEN 1 END)
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name LIKE 'IC[_]%';

-- ============================================================
-- PARTIE 3 — ALERTES : TABLES VIDES OU SUSPECTES
-- ============================================================
PRINT '';
PRINT '--- PARTIE 3 : ALERTES — TABLES VIDES ---';

-- Tables TFT vides (fichier CRE non chargé ?)
SELECT
    'TFT'                               AS [Base],
    t.name                              AS [Table vide],
    '🔴 Vérifier fichier CRE source'   AS [Action recommandée]
FROM TFT.sys.tables t
JOIN TFT.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
GROUP BY t.name
HAVING SUM(ps.row_count) = 0;

-- Tables ODS vides (traitement DATA STUDIO non exécuté ?)
SELECT
    'IC - ODS'                          AS [Base],
    t.name                              AS [Table vide],
    '🔴 Vérifier exécution DATA STUDIO TFT→ODS' AS [Action recommandée]
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name LIKE 'ODS[_]%'
GROUP BY t.name
HAVING SUM(ps.row_count) = 0;

-- Tables IC vides (traitement ODS→IC non exécuté ?)
SELECT
    'IC - IC'                           AS [Base],
    t.name                              AS [Table vide],
    '🔴 Vérifier exécution DATA STUDIO ODS→IC' AS [Action recommandée]
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name LIKE 'IC[_]%'
GROUP BY t.name
HAVING SUM(ps.row_count) = 0;

PRINT '';
PRINT '================================================================';
PRINT 'FIN SQL_ET_01 — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT 'Si perte de lignes détectée → SQL_ET_05_Find_Orphan_Records_RO.sql';
PRINT 'Si table TFT vide           → PS_ET_01_Check_CRE_Files_Status_RO.ps1';
PRINT '================================================================';
