/*
NOM: SQL_MC_03_Analyze_IO_By_Database_RO.sql | CAT: 06-MEMOIRE | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: I/O par base de donnees depuis demarrage SQL Server
       Identifier quelle base genere le plus de charge disque
*/
SET NOCOUNT ON;

-- I/O par fichier et base
SELECT
    DB_NAME(vfs.database_id)                AS [Base],
    mf.physical_name                        AS [Fichier physique],
    mf.type_desc                            AS [Type],
    vfs.io_stall_read_ms/NULLIF(vfs.num_of_reads,0) AS [Latence lect moy (ms)],
    vfs.io_stall_write_ms/NULLIF(vfs.num_of_writes,0) AS [Latence ecrit moy (ms)],
    vfs.num_of_reads                        AS [Nb lectures],
    vfs.num_of_writes                       AS [Nb ecritures],
    vfs.num_of_bytes_read/1024/1024         AS [Mo lus],
    vfs.num_of_bytes_written/1024/1024      AS [Mo ecrits],
    vfs.io_stall/1000                       AS [Stall total (s)],
    CASE
        WHEN vfs.io_stall_read_ms/NULLIF(vfs.num_of_reads,0) > 100
        THEN 'LATENCE LECTURE ELEVEE (>100ms) — disque sature ou reseau lent'
        WHEN vfs.io_stall_write_ms/NULLIF(vfs.num_of_writes,0) > 100
        THEN 'LATENCE ECRITURE ELEVEE (>100ms)'
        ELSE 'OK'
    END                                     AS [Diagnostic]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
ORDER BY vfs.io_stall DESC;
