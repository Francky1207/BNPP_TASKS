/*
NOM: SQL_JA_01_List_Failed_Jobs_Last24h_RO.sql | CAT: 09-JOBS | P0
TYPE: READ ONLY | PERMS: SQLAgentReaderRole
OBJET: Tous les jobs SQL Server Agent en echec dans les 24 dernieres heures
       Premiere chose a verifier le matin (controle RUN 8h30)
PARAM: @HeuresRetroactif (defaut 24)
*/
SET NOCOUNT ON;
DECLARE @HeuresRetroactif INT = 24;

SELECT
    j.name                                  AS [Nom job],
    jh.step_id                              AS [Etape],
    jh.step_name                            AS [Nom etape],
    CONVERT(DATETIME, CAST(jh.run_date AS VARCHAR) + ' ' +
        STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':')) AS [Heure execution],
    CASE jh.run_status
        WHEN 0 THEN 'ECHEC'
        WHEN 1 THEN 'Succes'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Annule'
        WHEN 4 THEN 'En cours'
    END                                     AS [Statut],
    jh.message                              AS [Message erreur],
    jh.run_duration/10000 * 3600
    + (jh.run_duration % 10000)/100 * 60
    + jh.run_duration % 100                 AS [Duree (secondes)]
FROM msdb.dbo.sysjobhistory jh
JOIN msdb.dbo.sysjobs j ON j.job_id = jh.job_id
WHERE jh.run_status = 0   -- 0 = echec uniquement
  AND CONVERT(DATETIME, CAST(jh.run_date AS VARCHAR) + ' ' +
      STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':'))
      >= DATEADD(HOUR, -@HeuresRetroactif, GETDATE())
ORDER BY jh.run_date DESC, jh.run_time DESC;
