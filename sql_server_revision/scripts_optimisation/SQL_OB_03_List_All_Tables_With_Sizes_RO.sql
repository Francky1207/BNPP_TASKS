/*
NOM: SQL_OB_03_List_All_Tables_With_Sizes_RO.sql | CAT: 08-OBJETS | P0
TYPE: READ ONLY | PERMS: VIEW DATABASE STATE
OBJET: Toutes les tables d'une base avec lignes et taille — SANS SCAN
       Vue d'ensemble complete pour identifier les tables volumineuses
PARAMS: @BaseCible, @FiltreNom ('' = toutes, 'ODS' = tables ODS*)
*/
SET NOCOUNT ON;
DECLARE @FiltreNom NVARCHAR(128) = '';  -- '' = toutes

SELECT
    t.name                                  AS [Table],
    SUM(ps.row_count)                       AS [Nb lignes],
    SUM(ps.used_page_count) * 8 / 1024     AS [Mo utilises],
    SUM(ps.reserved_page_count) * 8 / 1024 AS [Mo reserves],
    t.create_date                           AS [Cree le],
    t.modify_date                           AS [Modifie le],
    CASE
        WHEN SUM(ps.row_count) > 10000000 THEN 'VOLUMINEUSE > 10M lignes'
        WHEN SUM(ps.row_count) = 0        THEN 'VIDE'
        ELSE 'Normal'
    END                                     AS [Signal]
FROM sys.tables t
JOIN sys.dm_db_partition_stats ps ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE (@FiltreNom = '' OR t.name LIKE '%' + @FiltreNom + '%')
GROUP BY t.name, t.create_date, t.modify_date
ORDER BY SUM(ps.row_count) DESC;
