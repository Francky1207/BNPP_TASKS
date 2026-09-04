/*
NOM: SQL_CM_02_Compare_RowCounts_Two_Tables_RO.sql | CAT: 15-MESURES | P0
TYPE: READ ONLY | PERMS: VIEW DATABASE STATE
OBJET: Comparer le nombre de lignes de deux tables ou requetes
       Pour valider qu'une optimisation ne perd pas de donnees
*/
SET NOCOUNT ON;
DECLARE @Base1  NVARCHAR(128) = 'IC';
DECLARE @Table1 NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @Base2  NVARCHAR(128) = 'IC';
DECLARE @Table2 NVARCHAR(128) = 'IC_MOUVEMENTS';  -- <- Adapter

SELECT
    @Base1 + '.dbo.' + @Table1 AS [Table 1],
    SUM(ps.row_count) AS [Lignes T1]
FROM IC.sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID(@Base1 + '.dbo.' + @Table1)
  AND ps.index_id IN (0,1)

UNION ALL

SELECT
    @Base2 + '.dbo.' + @Table2,
    SUM(ps.row_count)
FROM IC.sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID(@Base2 + '.dbo.' + @Table2)
  AND ps.index_id IN (0,1);
