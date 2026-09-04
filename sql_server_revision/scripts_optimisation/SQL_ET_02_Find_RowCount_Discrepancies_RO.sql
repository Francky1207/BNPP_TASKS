/*
NOM: SQL_ET_02_Find_RowCount_Discrepancies_RO.sql | CAT: 10-ETL | P0
TYPE: READ ONLY | PERMS: db_datareader
OBJET: Detecter automatiquement les pertes ou doublons entre couches ETL
       Compare les volumes TFT vs ODS et ODS vs IC sur les tables homologues
       Utilise sys.dm_db_partition_stats — SANS SCAN (O(1) par table)
*/
SET NOCOUNT ON;

PRINT 'Comparaison volumes TFT vs ODS_* vs IC_* — ' + CONVERT(VARCHAR, GETDATE(), 120);

-- Volumes TFT
;WITH TFT_Volumes AS (
    SELECT t.name AS NomTable, SUM(ps.row_count) AS Lignes
    FROM TFT.sys.tables t
    JOIN TFT.sys.dm_db_partition_stats ps ON ps.object_id=t.object_id AND ps.index_id IN(0,1)
    GROUP BY t.name
),
ODS_Volumes AS (
    SELECT t.name AS NomTable, SUM(ps.row_count) AS Lignes
    FROM IC.sys.tables t
    JOIN IC.sys.dm_db_partition_stats ps ON ps.object_id=t.object_id AND ps.index_id IN(0,1)
    WHERE t.name LIKE 'ODS[_]%'
    GROUP BY t.name
),
IC_Volumes AS (
    SELECT t.name AS NomTable, SUM(ps.row_count) AS Lignes
    FROM IC.sys.tables t
    JOIN IC.sys.dm_db_partition_stats ps ON ps.object_id=t.object_id AND ps.index_id IN(0,1)
    WHERE t.name LIKE 'IC[_]%'
    GROUP BY t.name
)
-- Afficher couches ODS avec leur volume
SELECT
    'TFT' AS [Couche],
    NomTable AS [Table],
    Lignes AS [Nb lignes],
    CASE WHEN Lignes = 0 THEN 'VIDE' ELSE 'OK' END AS [Signal]
FROM TFT_Volumes
UNION ALL
SELECT 'ODS', NomTable, Lignes, CASE WHEN Lignes = 0 THEN 'VIDE' ELSE 'OK' END
FROM ODS_Volumes
UNION ALL
SELECT 'IC', NomTable, Lignes, CASE WHEN Lignes = 0 THEN 'VIDE' ELSE 'OK' END
FROM IC_Volumes
ORDER BY [Table], [Couche];
