/*
NOM: SQL_IX_03_Find_Unused_Indexes_RO.sql | CAT: 04-INDEX | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE + VIEW DEFINITION
OBJET: Index jamais utilises en lecture depuis le dernier redemarrage
       Ces index coutent en ecriture (INSERT/UPDATE/DELETE) sans apporter en lecture
       Candidats a la suppression apres validation DBA
PARAMS: @BaseCible, @MinUpdates (seuil d'ecriture pour etre pertinent)
NOTE: Resultats valides seulement si uptime suffisant (>1 semaine recommande)
*/
SET NOCOUNT ON;
DECLARE @BaseCible   NVARCHAR(128) = 'IC';
DECLARE @MinUpdates  INT           = 100;  -- ignorer index peu sollicites en ecriture aussi

SELECT
    DB_NAME()                               AS [Base],
    OBJECT_NAME(i.object_id)               AS [Table],
    i.name                                 AS [Index],
    i.type_desc                            AS [Type],
    ISNULL(us.user_seeks,  0)              AS [Seeks],
    ISNULL(us.user_scans,  0)              AS [Scans],
    ISNULL(us.user_lookups,0)              AS [Lookups],
    ISNULL(us.user_updates,0)              AS [Updates (cout)],
    us.last_user_seek                      AS [Dernier seek],
    us.last_user_scan                      AS [Dernier scan],
    -- Script DROP pret a l'emploi (valider avant execution !)
    'DROP INDEX [' + i.name + '] ON [dbo].[' + OBJECT_NAME(i.object_id) + '];' AS [Script DROP (a valider)]
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
    ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.type > 1                             -- exclure clustered et heap
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND ISNULL(us.user_seeks,  0) = 0
  AND ISNULL(us.user_scans,  0) = 0
  AND ISNULL(us.user_lookups,0) = 0
  AND ISNULL(us.user_updates,0) >= @MinUpdates
ORDER BY ISNULL(us.user_updates, 0) DESC;
