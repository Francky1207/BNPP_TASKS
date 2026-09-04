/*
============================================================
NOM          : SQL_BL_01_Analyze_Current_Blocking_RO.sql
CATEGORIE    : 05 - BLOCAGES ET VERROUS
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré SQL Server 2019, RCSI désactivé
============================================================

OBJECTIF :
  Analyse COMPLÈTE du blocking actif en ce moment.
  Répondre à : "Qui bloque qui, depuis combien de temps,
  avec quelle requête, et quel est l'impact total ?"

TYPE        : READ ONLY
RISQUE      : FAIBLE

PERMISSIONS : VIEW SERVER STATE

CONTEXTE SPÉCIFIQUE :
  ⚠️ RCSI désactivé sur votre environnement
  → Les lectures non isolées peuvent bloquer les écritures et vice-versa
  → Cela aggrave le blocking en production
  → Recommandation : activer RCSI (voir fin de script)

QUAND L'UTILISER :
  → Traitement DATA STUDIO anormalement long
  → Utilisateurs signalent que l'application ne répond plus
  → Script SQL bloqué sans message d'erreur
  → Après SQL_DI_01 si Section 5 détecte du blocking

RÉSULTATS :
  Partie 1 : Chaîne de blocking complète (qui bloque qui)
  Partie 2 : Détail des verrous actifs sur les tables concernées
  Partie 3 : Texte SQL du bloqueur ET des bloqués
  Partie 4 : Recommandation d'action

INTERPRÉTATION :
  blocking_session_id = 0  → c'est le bloqueur principal (la "racine")
  wait_type = LCK_M_X      → verrou exclusif (INSERT/UPDATE/DELETE)
  wait_type = LCK_M_S      → verrou partagé (SELECT sans RCSI)
  wait_type = LCK_M_U      → verrou de mise à jour

ETAPE SUIVANTE :
  Si le bloqueur est un SELECT → activer RCSI pour isoler les lectures
  Si le bloqueur est un INSERT/UPDATE → optimiser la transaction (la raccourcir)
  Si deadlock → SQL_BL_03_Find_Deadlock_In_SystemHealth_RO.sql
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- PARTIE 1 — CHAÎNE DE BLOCKING COMPLÈTE
-- ============================================================
PRINT '================================================================';
PRINT 'SQL_BL_01 — ANALYSE BLOCKING — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';
PRINT '';
PRINT '--- PARTIE 1 : CHAÎNE DE BLOCKING ---';

;WITH BlockingChain AS (
    -- Sessions racines (les vrais bloqueurs)
    SELECT
        s.session_id,
        s.login_name,
        s.host_name,
        CAST(0 AS INT)  AS blocking_session_id,
        DB_NAME(r.database_id) AS database_name,
        r.wait_type,
        r.wait_time / 1000 AS wait_sec,
        r.total_elapsed_time / 1000 AS elapsed_sec,
        r.cpu_time,
        r.logical_reads,
        r.status,
        r.command,
        'BLOQUEUR (racine)' AS role,
        0 AS niveau
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
    WHERE s.is_user_process = 1
      AND NOT EXISTS (
          SELECT 1 FROM sys.dm_exec_requests r2
          WHERE r2.session_id = s.session_id
            AND r2.blocking_session_id != 0
      )
      AND EXISTS (
          SELECT 1 FROM sys.dm_exec_requests r3
          WHERE r3.blocking_session_id = s.session_id
      )

    UNION ALL

    -- Sessions bloquées
    SELECT
        r.session_id,
        s.login_name,
        s.host_name,
        r.blocking_session_id,
        DB_NAME(r.database_id),
        r.wait_type,
        r.wait_time / 1000,
        r.total_elapsed_time / 1000,
        r.cpu_time,
        r.logical_reads,
        r.status,
        r.command,
        'BLOQUÉE' AS role,
        1 AS niveau
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
    WHERE r.blocking_session_id != 0
)
SELECT
    role                                AS [Rôle],
    session_id                          AS [Session],
    login_name                          AS [Login],
    host_name                           AS [Machine],
    database_name                       AS [Base],
    command                             AS [Commande],
    status                              AS [Statut],
    wait_type                           AS [Type attente],
    wait_sec                            AS [Attente (s)],
    elapsed_sec                         AS [Durée totale (s)],
    cpu_time / 1000                     AS [CPU (s)],
    logical_reads                       AS [Lectures logiques],
    blocking_session_id                 AS [Bloqué par]
FROM BlockingChain
ORDER BY niveau, session_id;

-- ============================================================
-- PARTIE 2 — VERROUS ACTIFS SUR LES OBJETS CONCERNÉS
-- ============================================================
PRINT '';
PRINT '--- PARTIE 2 : VERROUS ACTIFS PAR OBJET ---';

SELECT
    tl.request_session_id               AS [SessionId],
    DB_NAME(tl.resource_database_id)    AS [Base],
    tl.resource_type                    AS [Type ressource],
    OBJECT_NAME(p.object_id, tl.resource_database_id) AS [Objet (table)],
    tl.request_mode                     AS [Mode verrou],
    tl.request_status                   AS [Statut verrou],
    tl.resource_description             AS [Description ressource]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p
    ON p.hobt_id = tl.resource_associated_entity_id
WHERE tl.request_session_id != @@SPID
  AND tl.request_status IN ('WAIT', 'GRANT')
  AND tl.resource_type NOT IN ('DATABASE', 'METADATA')
ORDER BY tl.request_session_id, tl.request_status DESC;

-- ============================================================
-- PARTIE 3 — TEXTE SQL DES ACTEURS DU BLOCKING
-- ============================================================
PRINT '';
PRINT '--- PARTIE 3 : TEXTE SQL DES BLOQUEURS ET BLOQUÉS ---';

-- SQL du bloqueur principal
SELECT
    r.blocking_session_id               AS [SessionId bloqueur],
    'BLOQUEUR'                          AS [Rôle],
    t.text                              AS [Texte SQL complet]
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(
    (SELECT sql_handle FROM sys.dm_exec_requests r2
     WHERE r2.session_id = r.blocking_session_id)
) t
WHERE r.blocking_session_id != 0
GROUP BY r.blocking_session_id, t.text;

-- SQL des sessions bloquées
SELECT
    r.session_id                        AS [SessionId bloqué],
    'BLOQUÉ'                            AS [Rôle],
    r.wait_time / 1000                  AS [Attente (s)],
    t.text                              AS [Texte SQL en attente]
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id != 0
ORDER BY r.wait_time DESC;

-- ============================================================
-- PARTIE 4 — RECOMMANDATION
-- ============================================================
PRINT '';
PRINT '--- PARTIE 4 : RECOMMANDATIONS ---';
PRINT '';
PRINT 'Si le bloqueur est un SELECT :';
PRINT '  → Recommandation : activer RCSI sur la base concernée';
PRINT '  → Script à soumettre au DBA :';
PRINT '    ALTER DATABASE [NomBase] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;';
PRINT '  → Impact : les SELECT ne poseront plus de verrous S, éliminant cette catégorie de blocking';
PRINT '';
PRINT 'Si le bloqueur est un INSERT/UPDATE/DELETE long :';
PRINT '  → Vérifier si la transaction est vraiment nécessaire sur ce périmètre';
PRINT '  → Réduire la taille des transactions (traitement par lots)';
PRINT '  → Ajouter des index pour réduire la durée des opérations';
PRINT '';
PRINT 'Pour tuer la session bloquante (avec précaution !) :';
PRINT '  → Utiliser SQL_SR_07_Kill_Session_MOD.sql';
PRINT '  → Ou : KILL [session_id_du_bloqueur];';
PRINT '';
PRINT 'RAPPEL : RCSI est actuellement DÉSACTIVÉ sur votre environnement.';
PRINT 'Son activation est la mesure la plus efficace contre le blocking par SELECT.';
