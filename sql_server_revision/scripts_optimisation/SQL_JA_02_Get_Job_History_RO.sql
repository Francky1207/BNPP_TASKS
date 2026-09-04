/*
NOM: SQL_JA_02_Get_Job_History_RO.sql | CAT: 09-JOBS | P0
TYPE: READ ONLY | PERMS: SQLAgentReaderRole
OBJET: Historique complet d'un job avec durees successives
       Detecter une derive progressive (job qui prend de plus en plus de temps)
PARAM: @JobName, @NbDerniersRuns
*/
SET NOCOUNT ON;
DECLARE @JobName        NVARCHAR(256) = '';   -- <- Nom exact du job
DECLARE @NbDerniersRuns INT           = 30;

IF @JobName = '' BEGIN PRINT 'Definir @JobName'; RETURN; END

SELECT TOP (@NbDerniersRuns)
    j.name                                  AS [Job],
    CONVERT(DATETIME, CAST(jh.run_date AS VARCHAR) + ' ' +
        STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':')) AS [Debut],
    CASE jh.run_status WHEN 1 THEN 'OK' WHEN 0 THEN 'ECHEC' ELSE CAST(jh.run_status AS VARCHAR) END AS [Statut],
    jh.run_duration/10000 * 3600
    + (jh.run_duration % 10000)/100 * 60
    + jh.run_duration % 100                 AS [Duree (s)],
    jh.step_id                              AS [Etape],
    jh.step_name,
    jh.message
FROM msdb.dbo.sysjobhistory jh
JOIN msdb.dbo.sysjobs j ON j.job_id = jh.job_id
WHERE j.name = @JobName
ORDER BY jh.run_date DESC, jh.run_time DESC;
