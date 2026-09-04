/*
NOM: SQL_MC_02_Check_CPU_Usage_RO.sql | CAT: 06-MEMOIRE | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: CPU SQL Server vs CPU OS depuis 256 dernieres minutes (ring buffer)
       Identifier si SQL Server est responsable de la saturation CPU
*/
SET NOCOUNT ON;

-- CPU depuis le ring buffer (256 derniers intervalles de 1 minute)
;WITH RingBuffer AS (
    SELECT
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int') AS [SQL CPU %],
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int') AS [OS Idle %],
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]','int') AS [Other CPU %],
        DATEADD(ms, -1 * (x.ms_ticks - record.value('(./Record/@time)[1]','bigint')),
                GETDATE()) AS [Timestamp]
    FROM (
        SELECT CAST(record AS XML) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '%<SystemHealth>%'
    ) AS r
    CROSS JOIN sys.dm_os_sys_info x
)
SELECT TOP 30
    [Timestamp],
    [SQL CPU %],
    100 - [OS Idle %] - [SQL CPU %] AS [Autres process CPU %],
    [OS Idle %]                     AS [CPU libre %],
    CASE
        WHEN [SQL CPU %] > 90 THEN 'SQL SERVER SATURE — SQL_PQ_01'
        WHEN 100-[OS Idle %] > 90 THEN 'CPU OS SATURE — autre process Windows'
        WHEN [SQL CPU %] > 70 THEN 'SQL Server charge'
        ELSE 'Normal'
    END                             AS [Diagnostic]
FROM RingBuffer
ORDER BY [Timestamp] DESC;

-- CPU actuel par session
SELECT TOP 15
    s.session_id, s.login_name, DB_NAME(r.database_id) AS [Base],
    r.cpu_time/1000 AS [CPU session(s)],
    r.total_elapsed_time/1000 AS [Duree(s)],
    LEFT(t.text, 100) AS [SQL]
FROM sys.dm_exec_sessions s
JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
ORDER BY r.cpu_time DESC;
