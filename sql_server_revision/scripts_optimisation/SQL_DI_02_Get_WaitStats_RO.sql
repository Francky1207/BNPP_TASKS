/*
============================================================
NOM     : SQL_DI_02_Get_WaitStats_RO.sql
CAT     : 01 - DIAGNOSTIC INITIAL | PRIORITE : P0
TYPE    : READ ONLY | RISQUE : FAIBLE
PERMS   : VIEW SERVER STATE
OBJET   : Top 15 types d'attente — identifier LE goulot principal
          INTERPRETATION :
          LCK_M_*         → Blocking verrous   → SQL_BL_01
          PAGEIOLATCH_*   → I/O disque saturé  → SQL_MC_03
          RESOURCE_SEMAPHORE → Mémoire grants  → SQL_MC_01
          CXPACKET        → Parallélisme       → vérifier MAXDOP
          WRITELOG        → Journal LDF saturé → SQL_FS_02
          SOS_SCHEDULER_* → CPU saturé         → SQL_MC_02
============================================================
*/
SET NOCOUNT ON;

-- Réinitialiser les waits pour mesure fraîche (optionnel, décommente si besoin)
-- DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR); -- ⚠️ MOD — uniquement en test

SELECT TOP 15
    wait_type                               AS [Type attente],
    waiting_tasks_count                     AS [Nb occurrences],
    wait_time_ms / 1000                     AS [Attente totale (s)],
    max_wait_time_ms / 1000                 AS [Attente max (s)],
    CAST(wait_time_ms * 100.0
         / NULLIF(SUM(wait_time_ms) OVER (), 0)
         AS DECIMAL(5,2))                   AS [% du total],
    CASE
        WHEN wait_type LIKE 'LCK_%'              THEN '→ SQL_BL_01 : BLOCKING VERROUS'
        WHEN wait_type LIKE 'PAGEIOLATCH_%'      THEN '→ SQL_MC_03 : I/O DISQUE'
        WHEN wait_type = 'RESOURCE_SEMAPHORE'    THEN '→ SQL_MC_01 : MÉMOIRE INSUFFISANTE'
        WHEN wait_type IN ('CXPACKET','CXCONSUMER') THEN '→ Parallélisme — vérifier MAXDOP'
        WHEN wait_type = 'WRITELOG'              THEN '→ SQL_FS_02 : JOURNAL LDF'
        WHEN wait_type LIKE 'SOS_SCHEDULER%'    THEN '→ SQL_MC_02 : CPU SATURÉ'
        WHEN wait_type = 'ASYNC_NETWORK_IO'     THEN '→ Client lent ou réseau'
        WHEN wait_type LIKE 'HADR_%'            THEN '→ AlwaysOn / Mirroring'
        ELSE 'Normal ou bénin'
    END                                     AS [Diagnostic et étape suivante]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
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
    'SOSHOST_EVENT','SOSHOST_INTERNAL','SOSHOST_SLEEP',
    'SLEEP_BUFFERPOOL_SERIALIZATIONGUARD','REDO_THREAD_PENDING_WORK'
)
ORDER BY wait_time_ms DESC;
