/*
NOM: SQL_IX_04_Check_Index_Fragmentation_RO.sql | CAT: 04-INDEX | P0
TYPE: LOW RISK (scan partiel des pages) | PERMS: db_datareader
OBJET: Fragmentation de tous les index d'une table ou base entiere
       Determine si REORGANIZE (<30%) ou REBUILD (>30%) est necessaire
PARAMS: @BaseCible, @TableName (''=toute la base), @SeuilAlerte (%)
WARNING: Sur une base avec des tables de 45M lignes, passer @TableName
         sur une table specifique plutot que toute la base
*/
SET NOCOUNT ON;
DECLARE @BaseCible   NVARCHAR(128) = 'IC';
DECLARE @TableName   NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE'; -- '' = toute la base (LENT)
DECLARE @SeuilAlerte DECIMAL(5,2)  = 10.0;  -- alerter si > 10% fragmentation

SELECT
    OBJECT_NAME(ips.object_id)             AS [Table],
    i.name                                 AS [Index],
    i.type_desc                            AS [Type],
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)) AS [Frag %],
    ips.page_count                         AS [Nb pages],
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30
        THEN 'REBUILD — ALTER INDEX [' + i.name + '] ON dbo.' + OBJECT_NAME(ips.object_id) + ' REBUILD WITH (ONLINE=ON);'
        WHEN ips.avg_fragmentation_in_percent > 10
        THEN 'REORGANIZE — ALTER INDEX [' + i.name + '] ON dbo.' + OBJECT_NAME(ips.object_id) + ' REORGANIZE;'
        ELSE 'OK — aucune action'
    END                                    AS [Action recommandee]
FROM sys.dm_db_index_physical_stats(
    DB_ID(@BaseCible),
    CASE WHEN @TableName = '' THEN NULL ELSE OBJECT_ID(@BaseCible + '.dbo.' + @TableName) END,
    NULL, NULL, 'LIMITED'  -- LIMITED = rapide, pas besoin de DETAILED
) ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.avg_fragmentation_in_percent >= @SeuilAlerte
  AND ips.page_count > 100    -- ignorer les petits index (fragmentation non significative)
  AND i.type > 0
ORDER BY ips.avg_fragmentation_in_percent DESC;
