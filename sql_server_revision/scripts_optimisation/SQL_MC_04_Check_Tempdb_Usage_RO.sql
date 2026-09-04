/*
NOM: SQL_MC_04_Check_Tempdb_Usage_RO.sql | CAT: 06-MEMOIRE | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Utilisation tempdb — espace, qui consomme, objets internes
       Tempdb partage entre TOUTES les bases — un seul ETL lourd peut bloquer tout le monde
*/
SET NOCOUNT ON;

-- Espace tempdb
SELECT
    mf.physical_name,
    mf.type_desc,
    mf.size * 8/1024                        AS [Taille allouee (Mo)],
    CAST(FILEPROPERTY(mf.name,'SpaceUsed') AS BIGINT) * 8/1024 AS [Espace utilise (Mo)]
FROM tempdb.sys.database_files mf;

-- Sessions qui consomment le plus de tempdb
SELECT TOP 15
    s.session_id,
    s.login_name,
    DB_NAME(r.database_id)                  AS [Base requete],
    tsu.internal_objects_alloc_page_count/128 AS [Objets internes (Mo)],
    tsu.user_objects_alloc_page_count/128   AS [Objets user (Mo)],
    tsu.session_space_usage/128            AS [Espace session (Mo)],
    r.total_elapsed_time/1000              AS [Duree(s)],
    LEFT(t.text, 150)                      AS [SQL]
FROM sys.dm_db_session_space_usage tsu
JOIN sys.dm_exec_sessions s ON s.session_id = tsu.session_id
LEFT JOIN sys.dm_exec_requests r ON r.session_id = tsu.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE (tsu.internal_objects_alloc_page_count + tsu.user_objects_alloc_page_count) > 0
ORDER BY (tsu.internal_objects_alloc_page_count + tsu.user_objects_alloc_page_count) DESC;
