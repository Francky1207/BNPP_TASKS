/*
NOM: SQL_IX_05_Check_Statistics_Freshness_RO.sql | CAT: 04-INDEX | P0
TYPE: READ ONLY | PERMS: VIEW DEFINITION
OBJET: Date et qualite des statistiques par table
       Des stats obsoletes = mauvais plans d'execution = requetes lentes
       C'est souvent la cause de degrades apres un chargement massif (ETL)
PARAMS: @BaseCible, @TableName (''=toutes tables)
*/
SET NOCOUNT ON;
DECLARE @BaseCible  NVARCHAR(128) = 'IC';
DECLARE @TableName  NVARCHAR(128) = '';  -- '' = toutes les tables

SELECT
    OBJECT_NAME(s.object_id)               AS [Table],
    s.name                                 AS [Statistique],
    sp.last_updated                        AS [Derniere MAJ],
    sp.rows                                AS [Nb lignes (au moment MAJ)],
    sp.rows_sampled                        AS [Lignes echantillonnees],
    CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(5,1)) AS [% echantillon],
    sp.modification_counter                AS [Modif depuis derniere MAJ],
    DATEDIFF(DAY, sp.last_updated, GETDATE()) AS [Jours depuis MAJ],
    CASE
        WHEN sp.last_updated IS NULL
        THEN 'JAMAIS MISES A JOUR — UPDATE STATISTICS urgent'
        WHEN DATEDIFF(DAY, sp.last_updated, GETDATE()) > 30
        THEN 'OBSOLETES (>30j) — UPDATE STATISTICS recommande'
        WHEN sp.modification_counter > sp.rows * 0.20
        THEN 'INVALIDEES (>20% modif) — UPDATE STATISTICS recommande'
        WHEN sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) < 20
        THEN 'ECHANTILLON FAIBLE — reconsiderer fullscan'
        ELSE 'OK'
    END                                    AS [Diagnostic],
    'UPDATE STATISTICS dbo.' + OBJECT_NAME(s.object_id) + ' [' + s.name + '];' AS [Script MAJ]
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE (@TableName = '' OR OBJECT_NAME(s.object_id) = @TableName)
  AND OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY
    CASE WHEN sp.last_updated IS NULL THEN 0
         WHEN sp.modification_counter > sp.rows * 0.20 THEN 1
         WHEN DATEDIFF(DAY, sp.last_updated, GETDATE()) > 30 THEN 2
         ELSE 3 END,
    sp.modification_counter DESC;
