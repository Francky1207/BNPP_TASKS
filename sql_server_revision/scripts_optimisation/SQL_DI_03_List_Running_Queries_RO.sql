/*
============================================================
NOM     : SQL_DI_03_List_Running_Queries_RO.sql
CAT     : 01 - DIAGNOSTIC INITIAL | PRIORITE : P0
TYPE    : READ ONLY | RISQUE : FAIBLE
PERMS   : VIEW SERVER STATE
OBJET   : Toutes les requêtes utilisateurs EN COURS en ce moment
          Paramètre @SeuilSecondes : afficher seulement >= N secondes (défaut 0 = toutes)
============================================================
*/
SET NOCOUNT ON;

DECLARE @SeuilSecondes INT = 0;  -- 0 = toutes, 30 = seulement celles qui durent > 30s

SELECT
    r.session_id                            AS [Sess],
    s.login_name                            AS [Login],
    s.host_name                             AS [Machine],
    DB_NAME(r.database_id)                  AS [Base],
    r.status                                AS [Statut],
    r.command                               AS [Cmd],
    r.wait_type                             AS [Attente],
    r.total_elapsed_time / 1000             AS [Durée(s)],
    r.cpu_time / 1000                       AS [CPU(s)],
    r.logical_reads                         AS [LogReads],
    r.reads                                 AS [PhysReads],
    r.writes                                AS [Writes],
    r.blocking_session_id                   AS [BloquéPar],
    r.open_transaction_count                AS [TxOuvertes],
    r.percent_complete                      AS [%avance],
    CASE
        WHEN r.blocking_session_id > 0      THEN '🔴 BLOQUÉ'
        WHEN r.wait_type LIKE 'PAGEIOLATCH_%' THEN '🟡 I/O'
        WHEN r.logical_reads > 1000000      THEN '🟡 SCAN MASSIF'
        WHEN r.cpu_time > 30000             THEN '🟡 CPU ÉLEVÉ'
        ELSE '🟢 Normal'
    END                                     AS [Signal],
    LEFT(t.text, 300)                       AS [SQL (300 car.)]
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID
  AND r.total_elapsed_time / 1000 >= @SeuilSecondes
ORDER BY r.total_elapsed_time DESC;
