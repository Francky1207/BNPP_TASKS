/*
NOM: SQL_FS_01_Analyze_Database_Files_RO.sql | CAT: 07-FICHIERS | P0
TYPE: READ ONLY | PERMS: VIEW DATABASE STATE
OBJET: Taille, espace utilise, croissance auto des fichiers MDF/NDF/LDF
       Detecter un disque qui va saturer avant qu'il le fasse
*/
SET NOCOUNT ON;

SELECT
    DB_NAME(mf.database_id)                 AS [Base],
    mf.name                                 AS [Nom logique],
    mf.physical_name                        AS [Chemin physique],
    mf.type_desc                            AS [Type],
    mf.size * 8/1024                        AS [Taille allouee (Mo)],
    CAST(FILEPROPERTY(mf.name,'SpaceUsed') AS BIGINT)*8/1024 AS [Utilise (Mo)],
    mf.size*8/1024 - CAST(FILEPROPERTY(mf.name,'SpaceUsed') AS BIGINT)*8/1024 AS [Libre (Mo)],
    CAST(CAST(FILEPROPERTY(mf.name,'SpaceUsed') AS BIGINT)*100.0/mf.size AS DECIMAL(5,1)) AS [% rempli],
    CASE mf.is_percent_growth
        WHEN 1 THEN CAST(mf.growth AS VARCHAR) + ' %'
        ELSE CAST(mf.growth * 8/1024 AS VARCHAR) + ' Mo'
    END                                     AS [Croissance auto],
    mf.max_size                             AS [Taille max (pages)],
    CASE
        WHEN CAST(FILEPROPERTY(mf.name,'SpaceUsed') AS BIGINT)*100.0/mf.size > 90
        THEN 'CRITIQUE — > 90% plein'
        WHEN mf.growth = 0 THEN 'CROISSANCE DESACTIVEE — risque de saturation'
        WHEN mf.is_percent_growth = 1 AND mf.growth < 10 THEN 'Croissance % faible — risque fragmentations LDF'
        ELSE 'OK'
    END                                     AS [Diagnostic]
FROM sys.master_files mf
ORDER BY DB_NAME(mf.database_id), mf.type;
