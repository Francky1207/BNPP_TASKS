/*
NOM: SQL_SR_03_Find_Blocking_Chain_RO.sql | CAT: 02-SESSIONS | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Chaine de blocking hierarchique complete — arbre bloqueurs/bloques
*/
SET NOCOUNT ON;

;WITH Blocking AS (
    SELECT s.session_id, CAST(0 AS INT) AS blocked_by, 0 AS lvl,
           CAST(CAST(s.session_id AS VARCHAR(10)) AS VARCHAR(500)) AS chemin
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
      AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests r2
                      WHERE r2.session_id = s.session_id AND r2.blocking_session_id > 0)
      AND EXISTS (SELECT 1 FROM sys.dm_exec_requests r3 WHERE r3.blocking_session_id = s.session_id)
    UNION ALL
    SELECT r.session_id, r.blocking_session_id, b.lvl + 1,
           CAST(b.chemin + '>' + CAST(r.session_id AS VARCHAR(10)) AS VARCHAR(500))
    FROM sys.dm_exec_requests r
    JOIN Blocking b ON b.session_id = r.blocking_session_id
    WHERE r.blocking_session_id > 0
)
SELECT
    REPLICATE('  ', b.lvl) + CASE b.lvl WHEN 0 THEN 'BLOQUEUR' ELSE 'BLOQUE' END AS [Role],
    b.session_id                AS [Sess],
    b.blocked_by                AS [Par],
    b.chemin                    AS [Chaine],
    s.login_name                AS [Login],
    DB_NAME(r.database_id)      AS [Base],
    r.wait_type                 AS [Attente],
    r.wait_time/1000            AS [Attend(s)],
    r.total_elapsed_time/1000   AS [Duree(s)],
    r.logical_reads             AS [LogReads],
    LEFT(ISNULL(t.text,''), 200) AS [SQL]
FROM Blocking b
JOIN sys.dm_exec_sessions s ON s.session_id = b.session_id
LEFT JOIN sys.dm_exec_requests r ON r.session_id = b.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
ORDER BY b.chemin;
