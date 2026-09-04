/*
============================================================
NOM          : SQL_DI_01_Get_Server_Health_RO.sql
CATEGORIE    : 01 - DIAGNOSTIC INITIAL
PRIORITE     : P0 — À exécuter EN PREMIER face à tout incident
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré SQL Server 2019, Environnement IC/TFT
============================================================

OBJECTIF :
  Vue d'ensemble immédiate de la santé du serveur SQL Server.
  Répond en 30 secondes à la question : "Quel est le problème principal ?"
  Combine en un seul script : sessions, mémoire, CPU, waits, jobs actifs.

TYPE        : READ ONLY — aucune modification
RISQUE      : FAIBLE — DMV légères, pas de scan de tables volumineuses

PERMISSIONS NECESSAIRES :
  - VIEW SERVER STATE (sur l'instance)
  - VIEW DATABASE STATE

ENVIRONNEMENT COMPATIBLE :
  - SQL Server 2019 ✅ (version détectée sur votre serveur de recette)
  - SQL Server 2016/2017/2022 ✅

QUAND L'UTILISER :
  → Traitement DATA STUDIO qui tarde
  → Script bloqué depuis plusieurs heures (comme le 28/08)
  → Utilisateurs qui se plaignent de lenteur
  → Tout autre incident inexpliqué
  → Le matin en routine (contrôle RUN 8h30)

RÉSULTATS PRODUITS :
  Section 1 : Informations serveur (version, uptime, mémoire configurée)
  Section 2 : Sessions actives / inactives / en attente
  Section 3 : TOP 10 des types d'attente actuels
  Section 4 : Requêtes en cours depuis plus de 5 minutes
  Section 5 : Y a-t-il du blocking actif ?
  Section 6 : Utilisation mémoire SQL Server

INTERPRÉTATION :
  Section 3 (Waits) :
    - CXPACKET/CXCONSUMER → parallélisme excessif
    - LCK_M_*            → blocages verrous (vérifier Section 5)
    - PAGEIOLATCH_*       → pression I/O disque
    - RESOURCE_SEMAPHORE  → pression mémoire (memory grants)
    - WRITELOG            → journal transactionnel saturé

ETAPE SUIVANTE :
  Si blocking → SQL_BL_01_Analyze_Current_Blocking_RO.sql
  Si CPU      → SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql
  Si I/O      → SQL_MC_03_Analyze_IO_By_Database_RO.sql
  Si Memory   → SQL_MC_01_Check_Memory_Pressure_RO.sql

NOTES SPECIFIQUES A VOTRE ENVIRONNEMENT :
  - RCSI désactivé → les lectures peuvent bloquer les écrivains
  - Query Store désactivé → historique limité au plan cache
  - Bases cibles principales : TFT (CRE), IC (ODS+IC)
  - Table volumineuse connue : ODS_Mouvements ~45M lignes
============================================================
*/

SET NOCOUNT ON;

PRINT '================================================================';
PRINT 'SQL_DI_01 — DIAGNOSTIC INITIAL SERVEUR — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';

-- ============================================================
-- SECTION 1 — INFORMATIONS SERVEUR
-- ============================================================
PRINT '';
PRINT '--- SECTION 1 : INFORMATIONS SERVEUR ---';

SELECT
    'SQL Server Version'         AS Info,
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS Valeur
UNION ALL SELECT 'Edition',        CAST(SERVERPROPERTY('Edition')        AS NVARCHAR(100))
UNION ALL SELECT 'Niveau patch',   CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(50))
UNION ALL SELECT 'Nom instance',   CAST(SERVERPROPERTY('ServerName')     AS NVARCHAR(100))
UNION ALL SELECT 'Collation',      CAST(SERVERPROPERTY('Collation')      AS NVARCHAR(100))
UNION ALL SELECT 'RCSI activé (0=Non → risque blocage)', CAST(0 AS NVARCHAR(10)); -- confirmé à 0

-- Uptime du serveur
SELECT
    sqlserver_start_time                                                    AS [Démarrage SQL Server],
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE())                         AS [Uptime (heures)],
    cpu_count                                                               AS [Nb CPUs logiques],
    physical_memory_kb / 1024                                               AS [RAM physique (Mo)],
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)') AS [Mémoire max SQL (Mo)]
FROM sys.dm_os_sys_info;

-- ============================================================
-- SECTION 2 — SESSIONS ACTIVES
-- ============================================================
PRINT '';
PRINT '--- SECTION 2 : SESSIONS ---';

SELECT
    status                              AS [Statut],
    COUNT(*)                            AS [Nb sessions]
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY status
ORDER BY COUNT(*) DESC;

-- Sessions actives > 1 minute — aperçu rapide
SELECT TOP 10
    s.session_id                                                AS [SessionId],
    s.login_name                                                AS [Login],
    s.host_name                                                 AS [Machine],
    DB_NAME(r.database_id)                                      AS [Base],
    s.status                                                    AS [Statut session],
    r.status                                                    AS [Statut requête],
    r.wait_type                                                 AS [Type d'attente],
    r.total_elapsed_time / 1000                                 AS [Durée (s)],
    r.cpu_time / 1000                                           AS [CPU (s)],
    r.logical_reads                                             AS [Lectures logiques],
    r.blocking_session_id                                       AS [Bloqué par],
    LEFT(ISNULL(t.text, ''), 80)                               AS [Début requête]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND (r.status IS NOT NULL OR s.status != 'sleeping')
  AND r.total_elapsed_time / 1000 > 60    -- plus d'1 minute
ORDER BY r.total_elapsed_time DESC;

-- ============================================================
-- SECTION 3 — TOP WAITS (goulot d'étranglement principal)
-- ============================================================
PRINT '';
PRINT '--- SECTION 3 : TOP 10 TYPES D''ATTENTE (depuis dernier démarrage) ---';

SELECT TOP 10
    wait_type                               AS [Type attente],
    waiting_tasks_count                     AS [Nb occurrences],
    wait_time_ms / 1000                     AS [Attente totale (s)],
    max_wait_time_ms / 1000                 AS [Attente max (s)],
    CASE
        WHEN wait_type LIKE 'LCK_%'          THEN '⚠️ BLOCKING — vérifier Section 5'
        WHEN wait_type LIKE 'PAGEIOLATCH_%'  THEN '⚠️ I/O DISQUE — pression disque'
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN '⚠️ MÉMOIRE — memory grants insuffisants'
        WHEN wait_type IN ('CXPACKET','CXCONSUMER') THEN 'INFO — Parallélisme'
        WHEN wait_type = 'WRITELOG'          THEN '⚠️ LOG — journal transactionnel'
        WHEN wait_type LIKE 'SOS_SCHEDULER_%' THEN '⚠️ CPU — saturation processeur'
        ELSE 'Normal'
    END                                     AS [Interprétation]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    -- Attentes système bénignes à exclure
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE',
    'LAZYWRITER_SLEEP','LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT','BROKER_EVENTHANDLER',
    'CHECKPOINT_QUEUE','DBMIRROR_EVENTS_QUEUE','SQLTRACE_WAIT_ENTRIES',
    'WAIT_XTP_CKPT_CLOSE','CLR_SEMAPHORE','DBMIRROR_WORKER_QUEUE',
    'SOSHOST_EVENT','SOSHOST_INTERNAL','SOSHOST_SLEEP','SLEEP_BUFFERPOOL_SERIALIZATIONGUARD'
)
ORDER BY wait_time_ms DESC;

-- ============================================================
-- SECTION 4 — REQUÊTES EN COURS DEPUIS PLUS DE 5 MINUTES
-- ============================================================
PRINT '';
PRINT '--- SECTION 4 : REQUÊTES EN COURS > 5 MINUTES ---';

SELECT
    r.session_id                                                AS [SessionId],
    s.login_name                                                AS [Login],
    DB_NAME(r.database_id)                                      AS [Base],
    r.status                                                    AS [Statut],
    r.wait_type                                                 AS [Attente],
    r.total_elapsed_time / 1000                                 AS [Durée totale (s)],
    r.cpu_time / 1000                                           AS [CPU (s)],
    r.logical_reads                                             AS [Lectures logiques],
    r.reads                                                     AS [Lectures physiques],
    r.writes                                                    AS [Écritures],
    r.blocking_session_id                                       AS [Bloqué par],
    r.percent_complete                                          AS [% avancement],
    CASE r.command
        WHEN 'BACKUP DATABASE' THEN '💾 BACKUP'
        WHEN 'RESTORE DATABASE' THEN '💾 RESTORE'
        WHEN 'DBCC' THEN '🔧 DBCC'
        WHEN 'SELECT' THEN '📖 SELECT'
        WHEN 'INSERT' THEN '✏️ INSERT'
        WHEN 'UPDATE' THEN '✏️ UPDATE'
        WHEN 'DELETE' THEN '✏️ DELETE'
        ELSE r.command
    END                                                         AS [Commande],
    LEFT(ISNULL(t.text, 'N/A'), 200)                           AS [Début texte SQL]
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id != @@SPID
  AND r.total_elapsed_time / 1000 > 300   -- > 5 minutes
ORDER BY r.total_elapsed_time DESC;

-- ============================================================
-- SECTION 5 — BLOCKING ACTIF (LE PLUS URGENT)
-- ============================================================
PRINT '';
PRINT '--- SECTION 5 : BLOCKING ACTIF EN CE MOMENT ---';

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests
    WHERE blocking_session_id != 0 AND session_id != @@SPID
)
BEGIN
    PRINT '⚠️ BLOCKING DÉTECTÉ — Exécuter SQL_BL_01_Analyze_Current_Blocking_RO.sql';

    SELECT
        r.blocking_session_id                                   AS [Bloqueur (SessionId)],
        s_bloqueur.login_name                                   AS [Login bloqueur],
        r.session_id                                            AS [Bloqué (SessionId)],
        s.login_name                                            AS [Login bloqué],
        DB_NAME(r.database_id)                                  AS [Base],
        r.wait_type                                             AS [Type verrou],
        r.wait_time / 1000                                      AS [Attente (s)],
        r.total_elapsed_time / 1000                             AS [Durée totale (s)],
        LEFT(ISNULL(t.text, ''), 150)                          AS [SQL bloqué]
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
    LEFT JOIN sys.dm_exec_sessions s_bloqueur ON s_bloqueur.session_id = r.blocking_session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.blocking_session_id != 0
    ORDER BY r.wait_time DESC;
END
ELSE
BEGIN
    PRINT '✅ Aucun blocking actif détecté';
END

-- ============================================================
-- SECTION 6 — MÉMOIRE SQL SERVER
-- ============================================================
PRINT '';
PRINT '--- SECTION 6 : MÉMOIRE SQL SERVER ---';

SELECT
    physical_memory_in_use_kb / 1024                            AS [Mémoire utilisée (Mo)],
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)') AS [Max configuré (Mo)],
    CAST(physical_memory_in_use_kb / 1024.0
         / (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)')
         * 100 AS DECIMAL(5,1))                                 AS [% utilisation],
    page_fault_count                                            AS [Page faults (depuis démarrage)],
    CASE
        WHEN physical_memory_in_use_kb / 1024.0
             / (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)') > 0.90
        THEN '⚠️ PRESSION MÉMOIRE — > 90% utilisé'
        ELSE '✅ Mémoire OK'
    END                                                         AS [Diagnostic]
FROM sys.dm_os_process_memory;

PRINT '';
PRINT '================================================================';
PRINT 'FIN DU DIAGNOSTIC — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT 'En cas de blocking → SQL_BL_01_Analyze_Current_Blocking_RO.sql';
PRINT 'En cas de lenteur  → SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql';
PRINT '================================================================';
