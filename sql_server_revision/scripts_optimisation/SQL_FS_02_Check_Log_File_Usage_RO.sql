/*
NOM: SQL_FS_02_Check_Log_File_Usage_RO.sql | CAT: 07-FICHIERS | P0
TYPE: READ ONLY | PERMS: VIEW DATABASE STATE
OBJET: Utilisation du fichier journal (LDF) et pourquoi il ne peut pas etre reutilise
       log_reuse_wait_desc = LOG_BACKUP → pas de sauvegarde de journal planifiee
       log_reuse_wait_desc = ACTIVE_TRANSACTION → transaction longue ouverte
*/
SET NOCOUNT ON;

SELECT
    name                                    AS [Base],
    recovery_model_desc                     AS [Recovery model],
    log_reuse_wait_desc                     AS [Raison blocage journal],
    CASE log_reuse_wait_desc
        WHEN 'LOG_BACKUP'         THEN 'Planifier des sauvegardes de journal regulieres'
        WHEN 'ACTIVE_TRANSACTION' THEN 'SQL_SR_05 : transaction longue ouverte'
        WHEN 'ACTIVE_BACKUP_OR_RESTORE' THEN 'Backup en cours — normal'
        WHEN 'DATABASE_MIRRORING' THEN 'Mirroring/AlwaysOn — journal en attente de replay'
        WHEN 'NOTHING'            THEN 'OK — le journal peut etre reutilise'
        ELSE 'Investiguer'
    END                                     AS [Action recommandee]
FROM sys.databases
ORDER BY name;

-- Taille et remplissage du journal
SELECT
    DB_NAME() AS [Base actuelle],
    name, log_size_mb = SIZE * 8.0 / 1024,
    log_used_mb = FILEPROPERTY(name,'SpaceUsed') * 8.0 / 1024
FROM (SELECT name, SIZE FROM sysfiles WHERE groupid = 0) AS s;

-- Utilisation DBCC SQLPERF pour toutes les bases
DBCC SQLPERF(LOGSPACE);
