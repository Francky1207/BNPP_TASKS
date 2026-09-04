/*
NOM: SQL_PQ_03_Find_Top_Slow_Queries_Duration_RO.sql | CAT: 03-PERF | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Top N requetes par duree moyenne d'execution
       Utile pour identifier les requetes lentes meme si peu executees
*/
SET NOCOUNT ON;
DECLARE @TopN      INT          = 20;
DECLARE @BaseCible NVARCHAR(128)= '';
DECLARE @MinMs     INT          = 1000; -- ignorer requetes < 1 sec

SELECT TOP (@TopN)
    qs.total_elapsed_time/qs.execution_count/1000      AS [Duree moy (ms)],
    qs.total_elapsed_time/1000                         AS [Duree totale (ms)],
    qs.execution_count                                 AS [Nb exec],
    qs.total_worker_time/qs.execution_count/1000       AS [CPU moy (ms)],
    qs.total_logical_reads/qs.execution_count          AS [LogReads moy],
    CAST(qs.total_worker_time * 100.0
         / NULLIF(qs.total_elapsed_time,0) AS DECIMAL(5,1)) AS [% CPU/Duree],
    DB_NAME(qt.dbid)                                   AS [Base],
    qs.last_execution_time                             AS [Derniere exec],
    CASE
        WHEN qs.total_worker_time * 100.0 / NULLIF(qs.total_elapsed_time,0) < 10
            THEN 'ATTENTE — probable blocage ou I/O'
        WHEN qs.total_logical_reads/qs.execution_count > 1000000
            THEN 'SCAN MASSIF — verifier les index'
        ELSE 'CPU actif'
    END                                                AS [Diagnostic],
    LEFT(qt.text, 500)                                 AS [SQL]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.total_elapsed_time/qs.execution_count/1000 >= @MinMs
  AND (@BaseCible = '' OR DB_NAME(qt.dbid) = @BaseCible)
  AND qt.text NOT LIKE '%sys.dm_%'
ORDER BY qs.total_elapsed_time/qs.execution_count DESC;
