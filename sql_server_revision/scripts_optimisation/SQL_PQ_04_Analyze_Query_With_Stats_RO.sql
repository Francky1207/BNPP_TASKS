/*
============================================================
NOM          : SQL_PQ_04_Analyze_Query_With_Stats_RO.sql
CATEGORIE    : 03 - PERFORMANCES REQUÊTES
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré SQL Server 2019
============================================================

OBJECTIF :
  Mesurer avec précision le coût RÉEL d'une requête fournie :
  lectures logiques, lectures physiques, CPU, durée.
  Produire des PREUVES MESURABLES avant et après optimisation.

  C'est cet outil qui aurait permis de détecter le O(n²) du NOT IN
  en mesurant que les logical reads augmentaient à chaque itération.

TYPE        : LOW RISK (lecture de données — peut lire des tables volumineuses)
RISQUE      : MOYEN si appliqué sur une table de 45M lignes sans WHERE

PERMISSIONS : db_datareader, VIEW DATABASE STATE

QUAND L'UTILISER :
  → Vous avez une requête suspectée lente
  → Vous voulez mesurer l'impact AVANT/APRÈS un index
  → Vous voulez prouver qu'une requête coûte cher (preuves objectives)
  → Vous voulez comparer deux versions d'une même requête

COMMENT UTILISER CE SCRIPT :
  1. Coller votre requête à analyser dans la section "VOTRE REQUÊTE ICI"
  2. Exécuter le script COMPLET
  3. Lire les résultats SET STATISTICS dans l'onglet "Messages"
  4. Lire le plan d'exécution dans l'onglet "Execution plan"
  5. Comparer les chiffres AVANT optimisation et APRÈS

RÉSULTATS À ANALYSER (onglet Messages) :
  "Table '...'. Scan count N, logical reads N, physical reads N..."
  
  Logical reads élevés  → la requête lit beaucoup de pages = mauvais accès
  Physical reads > 0    → données pas en cache = pression I/O disque
  Scan count > 1        → scans multiples = souvent corrélé à un O(n²)

MÉTRIQUES DE RÉFÉRENCE :
  Logical reads < 1 000    → très bon
  Logical reads < 100 000  → acceptable
  Logical reads > 500 000  → investigation requise
  Logical reads > 5 000 000 → problème sérieux (comme le NOT IN sur 39M lignes)

INTERPRÉTATION DES MÉTRIQUES CLÉS :
  Scan count > 1 sur une table → la table est scannée plusieurs fois
  → Signe quasi-certain d'un problème O(n²) ou de jointure non optimale
  → Dans votre cas NOT IN : scan count = nb d'itérations de la boucle !

ETAPE SUIVANTE :
  Si logical reads très élevés → SQL_IX_01_Find_Missing_Indexes_RO.sql
  Si Scan au lieu de Seek      → revoir la requête (fonction sur colonne ? NOT IN ?)
  Si paramètre sniffing        → SQL_PQ_08_Analyze_Parameter_Sniffing_RO.sql
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- CONFIGURATION — Activer toutes les mesures
-- ============================================================
SET STATISTICS IO ON;       -- lectures logiques/physiques par table
SET STATISTICS TIME ON;     -- temps CPU et temps écoulé

-- Vider le cache de résultats pour une mesure à froid
-- DBCC DROPCLEANBUFFERS; -- ⚠️ UNIQUEMENT EN DEV/TEST, jamais en prod
-- DBCC FREEPROCCACHE;    -- ⚠️ UNIQUEMENT EN DEV/TEST, jamais en prod

-- ============================================================
-- MESURE AVANT EXÉCUTION
-- ============================================================
DECLARE @debut_cpu        INT = @@CPU_BUSY;
DECLARE @debut_io_reads   INT = @@IO_BUSY;
DECLARE @debut_heure      DATETIME2 = SYSDATETIME();

PRINT '================================================================';
PRINT 'MESURE DÉMARRÉE — ' + CONVERT(VARCHAR, @debut_heure, 121);
PRINT 'Consultez l''onglet "Messages" pour les statistics IO/TIME';
PRINT 'Activez le plan d''exécution réel (Ctrl+M) AVANT d''exécuter';
PRINT '================================================================';
PRINT '';

-- ============================================================
-- ► VOTRE REQUÊTE À ANALYSER ICI ◄
-- Remplacez ce SELECT par la requête que vous voulez mesurer
-- ============================================================

-- EXEMPLE 1 : Version lente (NOT IN — identifiée le 28/08/2026)
/*
INSERT INTO ODS_MOUVEMENTS_PERE (ID_CONTRAT, N_MOUVEMENT, N_MOUVEMENT_PERE, POL_QUEUE_ID)
SELECT TOP (100000)
    CAST(CTR.ID_CONTRAT AS INT),
    CAST(SOURCE.POL_OPERATION_ID AS INT),
    CAST(CASE WHEN SOURCE.POL_OPERATION_PID = 0 THEN NULL ELSE SOURCE.POL_OPERATION_PID END AS INT),
    CAST(SOURCE.POL_QUEUE_ID AS INT)
FROM TFT.dbo.TFT_K_POLICY_OPERATIONS AS SOURCE
INNER JOIN IC.dbo.ODS_CONTRATS_DAV AS CTR ON SOURCE.POLICY_ID = CTR.REFERENCE_EXTERNE_KELIA
    AND CTR.SOURCE = 2 AND SOURCE.ARCHIVED <> 2
WHERE SOURCE.POL_OPERATION_ID NOT IN (SELECT N_MOUVEMENT FROM IC.dbo.ODS_MOUVEMENTS_PERE);
*/

-- EXEMPLE 2 : Version optimisée (LEFT JOIN — remplace le NOT IN)
/*
INSERT INTO ODS_MOUVEMENTS_PERE (ID_CONTRAT, N_MOUVEMENT, N_MOUVEMENT_PERE, POL_QUEUE_ID)
SELECT TOP (100000)
    CAST(CTR.ID_CONTRAT AS INT),
    CAST(SOURCE.POL_OPERATION_ID AS INT),
    CAST(CASE WHEN SOURCE.POL_OPERATION_PID = 0 THEN NULL ELSE SOURCE.POL_OPERATION_PID END AS INT),
    CAST(SOURCE.POL_QUEUE_ID AS INT)
FROM TFT.dbo.TFT_K_POLICY_OPERATIONS AS SOURCE
INNER JOIN IC.dbo.ODS_CONTRATS_DAV AS CTR ON SOURCE.POLICY_ID = CTR.REFERENCE_EXTERNE_KELIA
    AND CTR.SOURCE = 2 AND SOURCE.ARCHIVED <> 2
LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp ON omp.N_MOUVEMENT = SOURCE.POL_OPERATION_ID
WHERE omp.N_MOUVEMENT IS NULL;
*/

-- ► REMPLACEZ PAR VOTRE REQUÊTE :
SELECT 'Remplacer ce SELECT par votre requête à analyser' AS [Instructions];

-- ============================================================
-- MESURE APRÈS EXÉCUTION
-- ============================================================
DECLARE @fin_heure DATETIME2 = SYSDATETIME();

PRINT '';
PRINT '================================================================';
PRINT 'MESURE TERMINÉE — ' + CONVERT(VARCHAR, @fin_heure, 121);
PRINT 'Durée totale : ' + CAST(DATEDIFF(MILLISECOND, @debut_heure, @fin_heure) AS VARCHAR) + ' ms';
PRINT '================================================================';
PRINT 'INTERPRÉTATION DES STATISTICS IO (onglet Messages) :';
PRINT '  Scan count 1    → OK, accès direct';
PRINT '  Scan count > 1  → TABLE SCANNÉE PLUSIEURS FOIS → problème O(n²) probable';
PRINT '  Logical reads   → plus c''est bas, mieux c''est';
PRINT '  Physical reads  → idéalement 0 (données en cache)';
PRINT '';
PRINT 'Si Scan count > 1 sur ODS_MOUVEMENTS_PERE → problème NOT IN identifié';
PRINT 'Solution : remplacer NOT IN par LEFT JOIN ... WHERE IS NULL';
PRINT '  + CREATE INDEX IX_ODS_MOUVEMENTS_PERE_N_MOUVEMENT ON IC.dbo.ODS_MOUVEMENTS_PERE(N_MOUVEMENT)';
PRINT '================================================================';

-- Désactiver les statistics
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
