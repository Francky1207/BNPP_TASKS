/*
NOM: SQL_SR_04_Get_Query_Text_From_Session_RO.sql | CAT: 02-SESSIONS | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Texte SQL complet + plan cache d'une session donnee
PARAM: @SessionId — session a inspecter (trouver via SQL_SR_01)
*/
SET NOCOUNT ON;
DECLARE @SessionId INT = 0; -- <- Remplacer par le session_id cible

IF @SessionId = 0
BEGIN PRINT 'Definir @SessionId. Trouver via SQL_SR_01 ou SQL_DI_03'; RETURN; END

-- Requete active
SELECT r.session_id, r.status, r.command, r.wait_type,
       r.total_elapsed_time/1000 AS [Duree(s)], r.cpu_time/1000 AS [CPU(s)],
       r.logical_reads, r.blocking_session_id, t.text AS [SQL complet]
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id = @SessionId;

-- Dernier batch execute
SELECT s.text AS [Dernier batch SQL]
FROM sys.dm_exec_connections c
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) s
WHERE c.session_id = @SessionId;

-- Infos session
SELECT session_id, login_name, host_name, program_name, status,
       open_transaction_count, transaction_isolation_level,
       last_request_start_time, last_request_end_time
FROM sys.dm_exec_sessions WHERE session_id = @SessionId;
