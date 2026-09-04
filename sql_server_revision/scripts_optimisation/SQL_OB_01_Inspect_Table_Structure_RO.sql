/*
NOM: SQL_OB_01_Inspect_Table_Structure_RO.sql | CAT: 08-OBJETS | P0
TYPE: READ ONLY | PERMS: VIEW DEFINITION
OBJET: Structure complete d'une table — colonnes, types, nullable, defauts, contraintes
PARAM: @TableName, @BaseName
*/
SET NOCOUNT ON;
DECLARE @TableName NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @BaseName  NVARCHAR(128) = 'IC';

-- Structure colonnes
SELECT
    c.column_id                             AS [N°],
    c.name                                  AS [Colonne],
    TYPE_NAME(c.user_type_id)               AS [Type],
    c.max_length                            AS [Longueur max],
    c.precision                             AS [Precision],
    c.scale                                 AS [Scale],
    c.is_nullable                           AS [Nullable],
    c.is_identity                           AS [Identity],
    OBJECT_NAME(c.default_object_id)        AS [Contrainte defaut],
    dc.definition                           AS [Valeur defaut]
FROM sys.columns c
LEFT JOIN sys.default_constraints dc ON dc.object_id = c.default_object_id
WHERE c.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)
ORDER BY c.column_id;

-- Informations generales
SELECT
    OBJECT_NAME(t.object_id)               AS [Table],
    t.create_date                           AS [Date creation],
    t.modify_date                           AS [Derniere modif],
    SUM(ps.row_count)                       AS [Nb lignes (estimees)],
    SUM(ps.used_page_count) * 8 / 1024     AS [Taille utilisee (Mo)],
    SUM(ps.reserved_page_count) * 8 / 1024 AS [Taille reservee (Mo)]
FROM sys.tables t
JOIN sys.dm_db_partition_stats ps ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)
GROUP BY t.object_id, t.create_date, t.modify_date;

-- Contraintes PK et FK
SELECT
    kc.name                                 AS [Contrainte],
    kc.type_desc                            AS [Type contrainte],
    COL_NAME(ic.object_id, ic.column_id)   AS [Colonne]
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
WHERE kc.parent_object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName)

UNION ALL

SELECT fk.name, 'FOREIGN KEY',
    COL_NAME(fkc.parent_object_id, fkc.parent_column_id)
    + ' -> ' + OBJECT_NAME(fkc.referenced_object_id)
    + '.' + COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
WHERE fk.parent_object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName);
