/*
NOM: SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql | CAT: 03-PERF | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Top N requetes par consommation CPU depuis le dernier redemarrage
       Source: plan cache (sys.dm_exec_query_stats) — Query Store desactive
PARAMS: @TopN, @BaseCible, @MinExecCount
NOTE: Les resultats disparaissent au redemarrage SQL Server
*/
SET NOCOUNT ON;
DECLARE @TopN         INT          = 20;
DECLARE @BaseCible    NVARCHAR(128)= '';
DECLARE @MinExecCount INT          = 1;

SELECT TOP (@TopN)
    qs.total_worker_time/1000                           AS [CPU total (ms)],
    qs.total_worker_time / qs.execution_count / 1000   AS [CPU moyen (ms)],
    qs.execution_count                                  AS [Nb executions],
    qs.total_elapsed_time/1000                          AS [Duree totale (ms)],
    qs.total_elapsed_time/qs.execution_count/1000       AS [Duree moyenne (ms)],
    qs.total_logical_reads / qs.execution_count         AS [LogReads moy],
    qs.total_physical_reads / qs.execution_count        AS [PhysReads moy],
    DB_NAME(qt.dbid)                                    AS [Base],
    qs.last_execution_time                              AS [Derniere exec],
    qs.creation_time                                    AS [Plan cree le],
    LEFT(qt.text, 500)                                  AS [SQL (500 car.)],
    CAST(qs.plan_handle AS VARBINARY(64))               AS [plan_handle]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.execution_count >= @MinExecCount
  AND (@BaseCible = '' OR DB_NAME(qt.dbid) = @BaseCible)
  AND qt.text NOT LIKE '%sys.dm_%'      -- exclure les scripts de monitoring eux-memes
ORDER BY qs.total_worker_time DESC;
