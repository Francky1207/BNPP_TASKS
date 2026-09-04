/*
NOM: SQL_CM_01_Benchmark_Before_After_RO.sql | CAT: 15-MESURES | P0
TYPE: LOW RISK | PERMS: db_datareader + VIEW SERVER STATE
OBJET: Template de mesure avant/apres une optimisation — preuves objectives
       Mesure : lectures logiques, physiques, CPU, duree, plan d'execution
       UTILISATION : Copier ce template, inserer votre requete, comparer les chiffres
*/
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- ============================================================
-- CONFIGURATION
-- ============================================================
DECLARE @description VARCHAR(200) = 'Test NOT IN vs LEFT JOIN sur ODS_MOUVEMENTS_PERE';
DECLARE @debut DATETIME2 = SYSDATETIME();

-- Vider le cache (UNIQUEMENT EN DEV/RECETTE — JAMAIS EN PROD)
-- DBCC DROPCLEANBUFFERS;
-- DBCC FREEPROCCACHE;

PRINT '================================================================';
PRINT 'BENCHMARK : ' + @description;
PRINT 'Debut     : ' + CONVERT(VARCHAR, @debut, 121);
PRINT 'IMPORTANT : Activer le plan reel (Ctrl+M) avant d''executer';
PRINT 'IMPORTANT : Lire les logical reads dans l''onglet Messages';
PRINT '================================================================';
PRINT '';

-- ============================================================
-- MESURE 1 : VERSION LENTE (exemple NOT IN)
-- ============================================================
PRINT '--- MESURE 1 : Version a tester ---';
DECLARE @debut1 DATETIME2 = SYSDATETIME();

-- ► INSERER ICI LA REQUETE A MESURER
SELECT 'Version 1 — inserer votre requete ici' AS [Instructions];

DECLARE @fin1 DATETIME2 = SYSDATETIME();
PRINT 'Version 1 : ' + CAST(DATEDIFF(MILLISECOND, @debut1, @fin1) AS VARCHAR) + ' ms';
PRINT '';

-- ============================================================
-- MESURE 2 : VERSION OPTIMISEE (exemple LEFT JOIN)
-- ============================================================
PRINT '--- MESURE 2 : Version optimisee ---';
DECLARE @debut2 DATETIME2 = SYSDATETIME();

-- ► INSERER ICI LA VERSION OPTIMISEE
SELECT 'Version 2 — inserer votre version optimisee' AS [Instructions];

DECLARE @fin2 DATETIME2 = SYSDATETIME();
PRINT 'Version 2 : ' + CAST(DATEDIFF(MILLISECOND, @debut2, @fin2) AS VARCHAR) + ' ms';
PRINT '';

-- ============================================================
-- RESULTAT COMPARE
-- ============================================================
PRINT '================================================================';
PRINT 'COMPARAISON :';
PRINT 'V1 : ' + CAST(DATEDIFF(MILLISECOND, @debut1, @fin1) AS VARCHAR) + ' ms';
PRINT 'V2 : ' + CAST(DATEDIFF(MILLISECOND, @debut2, @fin2) AS VARCHAR) + ' ms';
PRINT 'Comparer aussi les "Logical reads" dans l''onglet Messages';
PRINT '(Scan count > 1 = O(n2) — Scan count = 1 = O(n))';
PRINT '================================================================';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
