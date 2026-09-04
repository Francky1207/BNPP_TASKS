/*
NOM: SQL_BL_03_Find_Deadlock_In_SystemHealth_RO.sql | CAT: 05-BLOCKING | P0
TYPE: READ ONLY | PERMS: VIEW SERVER STATE
OBJET: Extraire les deadlocks captures automatiquement par SQL Server
       dans la session Extended Events 'system_health' (toujours active)
       Disponible meme sans Query Store — SQL Server 2012+
*/
SET NOCOUNT ON;

SELECT TOP 20
    xdr.value('@timestamp','datetime2')             AS [Date deadlock],
    xdr.value('(//deadlock/process/@id)[1]','varchar(50)') AS [Process victime],
    xdr.value('(//deadlock/process/@loginname)[1]','varchar(128)') AS [Login victime],
    xdr.value('(//deadlock/process/@hostname)[1]','varchar(128)') AS [Machine victime],
    xdr.value('(//deadlock/process/inputbuf)[1]','varchar(max)') AS [SQL victime],
    xdr.value('(//deadlock/process/@id)[2]','varchar(50)') AS [Process bloqueur],
    xdr.value('(//deadlock/process/@loginname)[2]','varchar(128)') AS [Login bloqueur],
    xdr.value('(//deadlock/process/inputbuf)[2]','varchar(max)') AS [SQL bloqueur],
    xdr.query('.')                                  AS [XML complet]
FROM (
    SELECT xdr = CAST(target_data AS XML)
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
) r
CROSS APPLY xdr.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr)
ORDER BY xdr.value('@timestamp','datetime2') DESC;
