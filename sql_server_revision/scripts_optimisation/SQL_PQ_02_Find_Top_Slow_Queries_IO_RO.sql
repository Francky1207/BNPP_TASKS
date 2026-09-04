/*
NOM: SQL_PQ_02_Find_Top_Slow_Queries_IO_RO.sql | CAT: 03-PERF | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Top N requetes par lectures logiques (I/O) depuis le redemarrage
       Une requete avec beaucoup de logical_reads fait des scans massifs
       → indice fort d'un index manquant ou d'un NOT IN problematique
*/
SET NOCOUNT ON;
DECLARE @TopN      INT          = 20;
DECLARE @BaseCible NVARCHAR(128)= '';

SELECT TOP (@TopN)
    qs.total_logical_reads                              AS [LogReads total],
    qs.total_logical_reads / qs.execution_count        AS [LogReads moyen],
    qs.total_physical_reads / qs.execution_count       AS [PhysReads moyen],
    qs.execution_count                                 AS [Nb exec],
    qs.total_worker_time/qs.execution_count/1000       AS [CPU moy (ms)],
    qs.total_elapsed_time/qs.execution_count/1000      AS [Duree moy (ms)],
    DB_NAME(qt.dbid)                                   AS [Base],
    qs.last_execution_time                             AS [Derniere exec],
    CASE
        WHEN qs.total_logical_reads/qs.execution_count > 5000000 THEN 'SCAN MASSIF — index manquant ou NOT IN'
        WHEN qs.total_logical_reads/qs.execution_count > 1000000 THEN 'Lectures elevees — investiguer'
        ELSE 'Acceptable'
    END                                                AS [Diagnostic],
    LEFT(qt.text, 500)                                 AS [SQL]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE (@BaseCible = '' OR DB_NAME(qt.dbid) = @BaseCible)
  AND qt.text NOT LIKE '%sys.dm_%'
ORDER BY qs.total_logical_reads DESC;
