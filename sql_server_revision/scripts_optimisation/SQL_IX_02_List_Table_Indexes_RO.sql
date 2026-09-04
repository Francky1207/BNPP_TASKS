/*
NOM: SQL_IX_02_List_Table_Indexes_RO.sql | CAT: 04-INDEX | P0
TYPE: READ ONLY | PERMS: VIEW DEFINITION
OBJET: Tous les index d'une table avec colonnes, type, fragmentation estimee
PARAM: @TableName (ex: 'ODS_MOUVEMENTS_PERE'), @BaseName (ex: 'IC')
*/
SET NOCOUNT ON;
DECLARE @TableName NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE'; -- <- Adapter
DECLARE @BaseName  NVARCHAR(128) = 'IC';                   -- <- Adapter

-- Index + colonnes
SELECT
    i.name                                  AS [Nom index],
    i.type_desc                             AS [Type],
    i.is_unique                             AS [Unique],
    i.is_primary_key                        AS [PK],
    COL_NAME(ic.object_id, ic.column_id)   AS [Colonne],
    ic.key_ordinal                          AS [Position],
    ic.is_included_column                   AS [INCLUDE],
    ic.is_descending_key                    AS [DESC]
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)
  AND i.type > 0
ORDER BY i.name, ic.key_ordinal;

-- Stats d'utilisation (depuis dernier redemarrage)
SELECT
    i.name                                  AS [Nom index],
    i.type_desc                             AS [Type],
    ISNULL(us.user_seeks, 0)               AS [Seeks],
    ISNULL(us.user_scans, 0)               AS [Scans],
    ISNULL(us.user_lookups, 0)             AS [Lookups],
    ISNULL(us.user_updates, 0)             AS [Updates (cout ecriture)],
    us.last_user_seek                       AS [Dernier seek],
    us.last_user_scan                       AS [Dernier scan],
    CASE
        WHEN ISNULL(us.user_seeks,0) + ISNULL(us.user_scans,0) = 0
             AND ISNULL(us.user_updates,0) > 0
        THEN 'Jamais lu, couteux en ecriture — candidat suppression'
        WHEN ISNULL(us.user_scans,0) > ISNULL(us.user_seeks,0) * 10
        THEN 'Beaucoup de scans — index peu selectif ou mal concu'
        ELSE 'OK'
    END                                     AS [Diagnostic]
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
    ON us.object_id = i.object_id AND us.index_id = i.index_id
    AND us.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)
  AND i.type > 0
ORDER BY i.name;
