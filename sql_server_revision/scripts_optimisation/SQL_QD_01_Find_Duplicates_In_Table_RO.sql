/*
NOM: SQL_QD_01_Find_Duplicates_In_Table_RO.sql | CAT: 11-QUALITE | P0
TYPE: READ ONLY | PERMS: db_datareader
OBJET: Trouver les doublons sur une ou plusieurs colonnes cles
       Adapte la colonne et la table aux besoins
PARAMS: @TableName, @BaseName, @ColonneCle
NOTE: Pour les tables volumineuses (45M lignes), toujours tester en
      filtrant d'abord sur un sous-ensemble (WHERE + TOP)
*/
SET NOCOUNT ON;
DECLARE @TableName  NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @BaseName   NVARCHAR(128) = 'IC';
DECLARE @TopDoublons INT = 100;  -- limiter pour ne pas saturer

-- Exemple sur N_MOUVEMENT (colonne cle de la table issue du 28/08/2026)
SELECT TOP (@TopDoublons)
    N_MOUVEMENT                             AS [Valeur dupliquee],
    COUNT(*) AS [Nb occurrences],
    MIN(ID_CONTRAT)                         AS [ID_Contrat exemple],
    MIN(POL_QUEUE_ID)                       AS [POL_QUEUE_ID exemple]
FROM IC.dbo.ODS_MOUVEMENTS_PERE
GROUP BY N_MOUVEMENT
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- Compter le total de doublons
SELECT
    COUNT(*) AS [Nb N_MOUVEMENT dupliques],
    SUM(nb-1) AS [Nb lignes en trop]
FROM (
    SELECT N_MOUVEMENT, COUNT(*) AS nb
    FROM IC.dbo.ODS_MOUVEMENTS_PERE
    GROUP BY N_MOUVEMENT
    HAVING COUNT(*) > 1
) d;
