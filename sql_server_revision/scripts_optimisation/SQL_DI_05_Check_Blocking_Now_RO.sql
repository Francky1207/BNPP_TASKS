/*
============================================================
NOM     : SQL_DI_05_Check_Blocking_Now_RO.sql
CAT     : 01 - DIAGNOSTIC INITIAL | PRIORITE : P0
TYPE    : READ ONLY | RISQUE : FAIBLE
PERMS   : VIEW SERVER STATE
OBJET   : Réponse binaire : y a-t-il du blocking en ce moment ?
          Si oui → quelles sessions, quelle durée, quel objet
          Usage : vérification rapide sans analyser tout le serveur
============================================================
*/
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE blocking_session_id > 0 AND session_id <> @@SPID)
BEGIN
    PRINT '⚠️ BLOCKING ACTIF DÉTECTÉ — ' + CONVERT(VARCHAR, GETDATE(), 120);
    PRINT 'Pour analyse complète → SQL_BL_01_Analyze_Current_Blocking_RO.sql';
    PRINT '';

    SELECT
        r.blocking_session_id               AS [Bloqueur],
        sb.login_name                       AS [Login bloqueur],
        r.session_id                        AS [Bloqué],
        s.login_name                        AS [Login bloqué],
        DB_NAME(r.database_id)              AS [Base],
        r.wait_type                         AS [Verrou],
        r.wait_time / 1000                  AS [Attente(s)],
        r.total_elapsed_time / 1000         AS [Durée totale(s)],
        LEFT(t.text, 200)                   AS [SQL bloqué]
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
    LEFT JOIN sys.dm_exec_sessions sb ON sb.session_id = r.blocking_session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.blocking_session_id > 0
    ORDER BY r.wait_time DESC;
END
ELSE
    PRINT '✅ Aucun blocking actif — ' + CONVERT(VARCHAR, GETDATE(), 120);
