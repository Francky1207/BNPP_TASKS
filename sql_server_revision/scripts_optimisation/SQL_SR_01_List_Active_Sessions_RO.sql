/*
NOM: SQL_SR_01_List_Active_Sessions_RO.sql | CAT: 02-SESSIONS | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Toutes les sessions utilisateurs actives avec etat detaille
PARAMS: @BaseFiltre (''=toutes), @ExclureIdle (1=exclure dormantes)
*/
SET NOCOUNT ON;
DECLARE @BaseFiltre  NVARCHAR(128) = '';
DECLARE @ExclureIdle BIT = 1;

SELECT
    s.session_id                                                AS [Sess],
    s.status                                                    AS [Etat],
    s.login_name                                                AS [Login],
    s.host_name                                                 AS [Machine],
    s.program_name                                              AS [Application],
    DB_NAME(ISNULL(r.database_id, s.database_id))              AS [Base],
    s.open_transaction_count                                    AS [Tx],
    ISNULL(r.status,'-')                                       AS [Etat req],
    ISNULL(r.command,'-')                                      AS [Cmd],
    ISNULL(r.wait_type,'-')                                    AS [Attente],
    ISNULL(r.total_elapsed_time/1000, 0)                       AS [Duree(s)],
    ISNULL(r.cpu_time/1000, 0)                                 AS [CPU(s)],
    ISNULL(r.logical_reads, 0)                                 AS [LogReads],
    ISNULL(r.blocking_session_id, 0)                           AS [BloquePar],
    s.last_request_start_time                                   AS [Debut],
    LEFT(ISNULL(t.text,''), 100)                               AS [SQL actuel]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND (@ExclureIdle = 0 OR r.session_id IS NOT NULL OR s.open_transaction_count > 0)
  AND (@BaseFiltre = '' OR DB_NAME(ISNULL(r.database_id,s.database_id)) = @BaseFiltre)
ORDER BY ISNULL(r.total_elapsed_time, 0) DESC;

SELECT
    COUNT(*)                                                    AS [Total sessions],
    SUM(CASE WHEN r.status='running' THEN 1 ELSE 0 END)        AS [Running],
    SUM(CASE WHEN r.blocking_session_id > 0 THEN 1 ELSE 0 END) AS [Bloquees],
    SUM(s.open_transaction_count)                               AS [Tx ouvertes]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
WHERE s.is_user_process = 1;
