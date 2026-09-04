/*
NOM: SQL_OB_02_Get_Table_RowCount_Size_RO.sql | CAT: 08-OBJETS | P0
TYPE: READ ONLY | PERMS: VIEW DATABASE STATE
OBJET: Nombre de lignes et taille d'une table specifique — SANS SCAN
       Utilise sys.dm_db_partition_stats (O(1) meme sur 45M lignes)
PARAM: @TableName, @BaseName
*/
SET NOCOUNT ON;
DECLARE @TableName NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @BaseName  NVARCHAR(128) = 'IC';

SELECT
    OBJECT_NAME(ps.object_id)              AS [Table],
    SUM(ps.row_count)                      AS [Nb lignes],
    SUM(ps.used_page_count) * 8 / 1024    AS [Taille donnees (Mo)],
    SUM(ps.reserved_page_count) * 8 / 1024 AS [Taille totale reservee (Mo)],
    (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024 AS [Espace libre interne (Mo)]
FROM sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)
  AND ps.index_id IN (0, 1)
GROUP BY ps.object_id;
