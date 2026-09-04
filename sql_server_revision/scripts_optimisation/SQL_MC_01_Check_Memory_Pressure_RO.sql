/*
NOM: SQL_MC_01_Check_Memory_Pressure_RO.sql | CAT: 06-MEMOIRE | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Pression memoire SQL Server — buffer pool, target, grants en attente
       Repond a: SQL Server manque-t-il de memoire ?
*/
SET NOCOUNT ON;

-- Configuration memoire
SELECT
    physical_memory_in_use_kb/1024          AS [RAM SQL utilisee (Mo)],
    (SELECT value_in_use FROM sys.configurations WHERE name='max server memory (MB)') AS [Max configure (Mo)],
    CAST(physical_memory_in_use_kb/1024.0
         /(SELECT value_in_use FROM sys.configurations WHERE name='max server memory (MB)')
         *100 AS DECIMAL(5,1))              AS [% utilisation],
    page_fault_count                        AS [Page faults],
    CASE WHEN physical_memory_in_use_kb/1024.0
              /(SELECT value_in_use FROM sys.configurations WHERE name='max server memory (MB)') > 0.90
         THEN 'PRESSION MEMOIRE > 90%'
         ELSE 'OK'
    END                                     AS [Diagnostic]
FROM sys.dm_os_process_memory;

-- Buffer pool par base
SELECT
    DB_NAME(database_id)                    AS [Base],
    COUNT(*) * 8 / 1024                     AS [Mo en buffer pool],
    COUNT(*)                                AS [Pages en memoire]
FROM sys.dm_os_buffer_descriptors
WHERE database_id <> 32767   -- exclure la ressource DB
GROUP BY database_id
ORDER BY COUNT(*) DESC;

-- Memory grants en attente (requetes qui manquent de memoire pour trier/hacher)
SELECT
    session_id, requested_memory_kb/1024   AS [Demande (Mo)],
    granted_memory_kb/1024                 AS [Accorde (Mo)],
    used_memory_kb/1024                    AS [Utilise (Mo)],
    wait_time_ms/1000                      AS [Attente (s)],
    queue_id
FROM sys.dm_exec_query_memory_grants
WHERE queue_id IS NOT NULL;   -- queue_id non null = en attente
