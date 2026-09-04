/*
NOM: SQL_QD_02_Check_Null_Coverage_RO.sql | CAT: 11-QUALITE | P0
TYPE: READ ONLY | PERMS: db_datareader
OBJET: Pourcentage de NULL par colonne dans une table
       Detecter les colonnes avec trop de valeurs manquantes
PARAM: @TableName, @BaseName, @SeuilAlerte (% NULL pour alerter)
WARNING: Lent sur les tables volumineuses — toujours specifier @TopRows
*/
SET NOCOUNT ON;
DECLARE @TableName  NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @BaseName   NVARCHAR(128) = 'IC';
DECLARE @SeuilAlerte DECIMAL(5,1) = 10.0;  -- alerter si > 10% de NULL
DECLARE @TopRows    INT           = 100000; -- echantillon (ne pas scanner 45M lignes)

PRINT 'Analyse NULL sur echantillon TOP ' + CAST(@TopRows AS VARCHAR) + ' lignes';
PRINT 'Table : ' + @BaseName + '.dbo.' + @TableName;
PRINT '';

-- Construction dynamique pour s'adapter a n'importe quelle table
DECLARE @sql NVARCHAR(MAX) = '';
SELECT @sql = @sql +
    'SELECT ''' + c.name + ''' AS Colonne, ' +
    'CAST(SUM(CASE WHEN ' + QUOTENAME(c.name) + ' IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,1)) AS [% NULL], ' +
    'COUNT(*) AS [Nb lignes echantillon] ' +
    'FROM (SELECT TOP (' + CAST(@TopRows AS VARCHAR) + ') ' + QUOTENAME(c.name) +
    ' FROM ' + @BaseName + '.dbo.' + @TableName + ') s UNION ALL '
FROM sys.columns c
WHERE c.object_id = OBJECT_ID(@BaseName + '.dbo.' + @TableName);

-- Retirer le dernier UNION ALL
SET @sql = LEFT(@sql, LEN(@sql) - 10);
SET @sql = 'SELECT Colonne, [% NULL], [Nb lignes echantillon], CASE WHEN [% NULL] > ' +
           CAST(@SeuilAlerte AS VARCHAR) + ' THEN ''ALERTE'' ELSE ''OK'' END AS Signal FROM (' +
           @sql + ') x ORDER BY [% NULL] DESC';

EXEC sp_executesql @sql;
