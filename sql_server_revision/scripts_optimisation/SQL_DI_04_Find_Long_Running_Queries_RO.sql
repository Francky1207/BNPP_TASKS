/*
============================================================
NOM          : SQL_DI_04_Find_Long_Running_Queries_RO.sql
CATEGORIE    : 01 - DIAGNOSTIC INITIAL
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré SQL Server 2019
============================================================

OBJECTIF :
  Lister toutes les requêtes SQL en cours depuis plus de N minutes,
  avec texte SQL complet, plan d'exécution et détails de consommation.
  Répondre à la question : "Ce script est-il encore en vie, ou bloqué ?"

  CONTEXTE DIRECT : Exactement la situation du 28/08/2026 — le script
  NOT IN qui tournait depuis 20h sans fin visible.

TYPE        : READ ONLY
RISQUE      : FAIBLE

PERMISSIONS : VIEW SERVER STATE

PARAMETRES :
  @MinDureeMinutes  — durée minimum en minutes (défaut : 10)
  @BaseFiltre       — filtrer sur une base spécifique ('' = toutes)

UTILISATION :
  -- Voir tout ce qui tourne depuis plus de 10 min, toutes bases
  EXEC(@MinDureeMinutes = 10, @BaseFiltre = '')

  -- Voir uniquement les requêtes sur la base IC depuis plus de 30 min
  EXEC(@MinDureeMinutes = 30, @BaseFiltre = 'IC')

RÉSULTATS :
  - Durée réelle de la requête
  - CPU consommé (très utile : si CPU élevé → la requête tourne vraiment)
  - Lectures logiques (très élevé → la requête scanne beaucoup)
  - % d'avancement (disponible pour BACKUP/DBCC/certaines opérations)
  - Texte SQL complet
  - Signe distinctif : bloqué ou en exécution réelle ?

INTERPRÉTATION :
  CPU élevé + logical reads élevés → requête qui tourne (pas bloquée)
  CPU = 0 + wait_type LCK_*       → requête BLOQUÉE par verrou
  CPU = 0 + wait_type PAGEIOLATCH  → disque saturé
  percent_complete > 0            → opération qui avance (BACKUP, etc.)

ETAPE SUIVANTE :
  Si bloqué : SQL_BL_01_Analyze_Current_Blocking_RO.sql
  Si en cours mais lent : SQL_PQ_04_Analyze_Query_With_Stats_RO.sql
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- PARAMÈTRES (modifier ici)
-- ============================================================
DECLARE @MinDureeMinutes INT = 10;      -- Afficher requêtes > 10 minutes
DECLARE @BaseFiltre      NVARCHAR(128) = '';   -- '' = toutes les bases

-- ============================================================
-- REQUÊTES EN COURS DEPUIS PLUS DE @MinDureeMinutes
-- ============================================================
SELECT
    r.session_id                                                AS [SessionId],
    s.login_name                                                AS [Login],
    s.host_name                                                 AS [Machine cliente],
    DB_NAME(r.database_id)                                      AS [Base],
    r.command                                                   AS [Commande],
    r.status                                                    AS [Statut],

    -- Durée et performance
    r.total_elapsed_time / 1000                                 AS [Durée totale (s)],
    r.total_elapsed_time / 60000                                AS [Durée (min)],
    r.cpu_time / 1000                                           AS [CPU consommé (s)],
    r.logical_reads                                             AS [Lectures logiques],
    r.reads                                                     AS [Lectures physiques],
    r.writes                                                    AS [Écritures],

    -- Indicateurs de diagnostic
    r.wait_type                                                 AS [Type d'attente],
    r.wait_time / 1000                                          AS [Temps attente actuel (s)],
    r.blocking_session_id                                       AS [Bloqué par (0=non)],
    r.percent_complete                                          AS [% avancement],

    -- Diagnostics calculés
    CASE
        WHEN r.blocking_session_id != 0
            THEN '🔴 BLOQUÉ par session ' + CAST(r.blocking_session_id AS VARCHAR)
        WHEN r.wait_type LIKE 'LCK_%'
            THEN '🔴 ATTENTE VERROU — probable blocking'
        WHEN r.wait_type LIKE 'PAGEIOLATCH_%'
            THEN '🟡 ATTENTE I/O — disque potentiellement saturé'
        WHEN r.cpu_time > r.total_elapsed_time * 0.8
            THEN '🟡 FORTE CONSOMMATION CPU — requête active'
        WHEN r.logical_reads > 10000000
            THEN '🟡 SCAN MASSIF — ' + CAST(r.logical_reads AS VARCHAR) + ' lectures logiques'
        ELSE '🟢 En cours d''exécution'
    END                                                         AS [Diagnostic],

    -- Texte SQL complet
    t.text                                                      AS [Texte SQL complet],

    -- Infos complémentaires session
    s.transaction_isolation_level                               AS [Isolation (1=ReadUncommitted..4=Serializable)],
    s.open_transaction_count                                    AS [Transactions ouvertes],
    s.last_request_start_time                                   AS [Début requête]

FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s
    ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id != @@SPID
  AND r.total_elapsed_time / 60000 >= @MinDureeMinutes
  AND (
    @BaseFiltre = ''
    OR DB_NAME(r.database_id) = @BaseFiltre
  )
ORDER BY r.total_elapsed_time DESC;

-- ============================================================
-- RÉSUMÉ CHIFFRÉ
-- ============================================================
PRINT '--- RÉSUMÉ ---';
SELECT
    COUNT(*)                                                    AS [Nb requêtes longues],
    MAX(r.total_elapsed_time / 60000)                           AS [Durée max (min)],
    SUM(CASE WHEN r.blocking_session_id != 0 THEN 1 ELSE 0 END) AS [Nb bloquées],
    SUM(CASE WHEN r.blocking_session_id = 0 THEN 1 ELSE 0 END)  AS [Nb en exécution réelle]
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE r.session_id != @@SPID
  AND r.total_elapsed_time / 60000 >= @MinDureeMinutes
  AND (
    @BaseFiltre = ''
    OR DB_NAME(r.database_id) = @BaseFiltre
  );
