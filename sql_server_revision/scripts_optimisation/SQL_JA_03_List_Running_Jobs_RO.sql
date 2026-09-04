/*
NOM: SQL_JA_03_List_Running_Jobs_RO.sql | CAT: 09-JOBS | P0
TYPE: READ ONLY | PERMS: SQLAgentReaderRole
OBJET: Jobs SQL Server Agent en cours d'execution en ce moment
       Verifier qu'un job ETL est bien en train de tourner ou detecter un job zombie
*/
SET NOCOUNT ON;

EXEC msdb.dbo.sp_help_job @execution_status = 1;  -- 1 = en cours d'execution

-- Alternative manuelle avec plus de details
SELECT
    j.name                                  AS [Job],
    ja.start_execution_date                 AS [Debut execution],
    DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS [Duree actuelle (min)],
    ja.last_executed_step_id               AS [Derniere etape executee],
    ja.last_executed_step_date             AS [Heure derniere etape],
    ja.next_scheduled_run_date             AS [Prochain run]
FROM msdb.dbo.sysjobactivity ja
JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
WHERE ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
  AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);
