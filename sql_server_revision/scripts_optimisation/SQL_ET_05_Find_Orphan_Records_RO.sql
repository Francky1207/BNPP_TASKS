/*
============================================================
NOM          : SQL_ET_05_Find_Orphan_Records_RO.sql
CATEGORIE    : 10 - ETL / CHAÎNE DE TRAITEMENT
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré pour tables volumineuses (45M+ lignes)
============================================================

OBJECTIF :
  Trouver les lignes présentes dans une table source (TFT/ODS)
  mais absentes de la table cible (ODS/IC).
  
  ⚠️ ATTENTION — CE SCRIPT EST LA VERSION CORRECTE DU PATTERN NOT IN.
  
  Le script NOT IN vu le 28/08/2026 faisait exactement ça mais avec
  un O(n²) catastrophique. Ce script fait la même chose en O(n)
  grâce au LEFT JOIN.

TYPE        : READ ONLY
RISQUE      : MOYEN — peut être long sur des tables de 45M+ lignes
              → Toujours exécuter avec un TOP pour estimer d'abord
              → Voir paramètre @ModeEstimation

PERMISSIONS : db_datareader

PARAMÈTRES :
  @BaseSource      — base SQL de la table source (ex: 'TFT', 'IC')
  @TableSource     — table source (ex: 'ODS_MOUVEMENTS_PERE')
  @ColSource       — colonne clé dans la source (ex: 'N_MOUVEMENT')
  @BaseCible       — base SQL de la table cible (ex: 'IC')
  @TableCible      — table cible (ex: 'IC_MOUVEMENTS')
  @ColCible        — colonne correspondante dans la cible (ex: 'N_MOUVEMENT')
  @TopEstimation   — nb de lignes orphelines à afficher (défaut: 100)
  @ModeEstimation  — 1 = COUNT seulement (rapide), 0 = données complètes

UTILISATION :
  -- Mode estimation rapide (combien d'orphelins ?)
  @ModeEstimation = 1   → seulement le COUNT, très rapide

  -- Mode données complètes (voir les lignes orphelines)
  @ModeEstimation = 0, @TopEstimation = 1000

RÉSULTATS :
  En mode estimation : le COUNT des lignes orphelines
  En mode données   : les lignes présentes en source mais absentes en cible

POURQUOI CE SCRIPT EST MEILLEUR QUE NOT IN :
  NOT IN → Pour chaque ligne de la source, scan complet de la cible → O(n²)
  LEFT JOIN → Jointure en hash une seule fois → O(n)
  Sur 45M lignes : NOT IN = 20h+, LEFT JOIN = quelques minutes

ETAPE SUIVANTE :
  Si beaucoup d'orphelins → investiguer les règles de jointure du script ETL
  Si 0 orphelins          → la chaîne est complète, problème ailleurs
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- PARAMÈTRES — À ADAPTER SELON LA PAIRE À INVESTIGUER
-- ============================================================
DECLARE @BaseSource      NVARCHAR(128) = 'TFT';
DECLARE @TableSource     NVARCHAR(128) = 'TFT_K_POLICY_OPERATIONS';
DECLARE @ColSource       NVARCHAR(128) = 'POL_OPERATION_ID';

DECLARE @BaseCible       NVARCHAR(128) = 'IC';
DECLARE @TableCible      NVARCHAR(128) = 'ODS_MOUVEMENTS_PERE';
DECLARE @ColCible        NVARCHAR(128) = 'N_MOUVEMENT';

DECLARE @TopEstimation   INT           = 100;    -- lignes à afficher
DECLARE @ModeEstimation  BIT           = 1;      -- 1=COUNT rapide, 0=données

PRINT '================================================================';
PRINT 'SQL_ET_05 — RECHERCHE LIGNES ORPHELINES (LEFT JOIN — O(n))';
PRINT 'Source : ' + @BaseSource + '.' + @TableSource + '.' + @ColSource;
PRINT 'Cible  : ' + @BaseCible + '.' + @TableCible + '.' + @ColCible;
PRINT 'Horodatage : ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '================================================================';

-- ============================================================
-- VÉRIFICATION PRÉALABLE — Volumes des deux tables
-- (sans scan — sys.dm_db_partition_stats)
-- ============================================================
PRINT '';
PRINT '--- PRÉ-CONTRÔLE : VOLUMES DES DEUX TABLES ---';

-- Cette requête est rapide car elle lit les métadonnées, pas les lignes
SELECT
    'SOURCE — ' + @BaseSource + '.' + @TableSource  AS [Table],
    SUM(ps.row_count)                                AS [Nb lignes estimé]
FROM IC.sys.tables t   -- note : remplacer par @BaseSource si différent
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name = @TableSource
GROUP BY t.name

UNION ALL

SELECT
    'CIBLE — ' + @BaseCible + '.' + @TableCible,
    SUM(ps.row_count)
FROM IC.sys.tables t
JOIN IC.sys.dm_db_partition_stats ps
    ON ps.object_id = t.object_id AND ps.index_id IN (0,1)
WHERE t.name = @TableCible
GROUP BY t.name;

-- ============================================================
-- EXEMPLE CONCRET PRÊT À L'EMPLOI
-- Paire TFT_K_POLICY_OPERATIONS → ODS_MOUVEMENTS_PERE
-- (exactement la paire du script du 28/08/2026)
-- ============================================================

PRINT '';
PRINT '--- EXEMPLE : POL_OPERATION_ID présents en TFT mais absents en ODS ---';
PRINT 'Version O(n) — LEFT JOIN — optimisée pour gros volumes';
PRINT '';

-- MODE 1 : Comptage rapide seulement (recommandé en premier)
IF @ModeEstimation = 1
BEGIN
    PRINT 'MODE ESTIMATION — COUNT seulement';
    PRINT 'Changer @ModeEstimation = 0 pour voir les lignes orphelines';
    PRINT '';

    -- Cette requête utilise un hash join, nettement plus efficace que NOT IN
    SELECT
        'POL_OPERATION_ID sans ODS_MOUVEMENTS'  AS [Paire analysée],
        COUNT(*)                                 AS [Nb lignes orphelines],
        CASE
            WHEN COUNT(*) = 0
            THEN '✅ Chaîne complète — aucune orpheline'
            WHEN COUNT(*) < 1000
            THEN '🟡 Quelques orphelines — vérifier les règles de jointure'
            ELSE '🔴 Pertes significatives — investigation requise'
        END                                      AS [Diagnostic]
    FROM TFT.dbo.TFT_K_POLICY_OPERATIONS src
    INNER JOIN IC.dbo.ODS_CONTRATS_DAV CTR
        ON CTR.REFERENCE_EXTERNE_KELIA = src.POLICY_ID
        AND CTR.SOURCE = 2
        AND src.ARCHIVED <> 2
    LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp
        ON omp.N_MOUVEMENT = src.POL_OPERATION_ID    -- ← LEFT JOIN au lieu de NOT IN
    WHERE omp.N_MOUVEMENT IS NULL;                    -- ← IS NULL au lieu de NOT IN
END

-- MODE 2 : Voir les lignes orphelines (TOP pour ne pas saturer)
IF @ModeEstimation = 0
BEGIN
    PRINT 'MODE DONNÉES — Top ' + CAST(@TopEstimation AS VARCHAR) + ' lignes orphelines';
    PRINT '';

    SELECT TOP (@TopEstimation)
        src.POL_OPERATION_ID    AS [N_MOUVEMENT manquant en ODS],
        src.POLICY_ID           AS [POLICY_ID source],
        src.POL_OPERATION_PID   AS [N_MOUVEMENT_PERE source],
        src.ARCHIVED            AS [ARCHIVED source],
        CTR.ID_CONTRAT          AS [ID_CONTRAT trouvé en ODS_CONTRATS]
    FROM TFT.dbo.TFT_K_POLICY_OPERATIONS src
    INNER JOIN IC.dbo.ODS_CONTRATS_DAV CTR
        ON CTR.REFERENCE_EXTERNE_KELIA = src.POLICY_ID
        AND CTR.SOURCE = 2
        AND src.ARCHIVED <> 2
    LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp
        ON omp.N_MOUVEMENT = src.POL_OPERATION_ID
    WHERE omp.N_MOUVEMENT IS NULL;
END

-- ============================================================
-- RAPPEL : SCRIPT D'INSERTION OPTIMISÉ (O(n) au lieu de O(n²))
-- ============================================================
PRINT '';
PRINT '================================================================';
PRINT 'RAPPEL : VERSION CORRECTE DU SCRIPT D''INSERTION (O(n))';
PRINT '================================================================';
PRINT '
-- ⚠️ RECOMMANDATION : ajouter d''abord cet index si absent
-- CREATE INDEX IX_ODS_MOUVEMENTS_PERE_N_MOUVEMENT
--     ON IC.dbo.ODS_MOUVEMENTS_PERE(N_MOUVEMENT);

-- Script d''insertion optimisé (remplace le NOT IN par LEFT JOIN)
WHILE 1 = 1
BEGIN
    INSERT INTO IC.dbo.ODS_MOUVEMENTS_PERE (ID_CONTRAT, N_MOUVEMENT, N_MOUVEMENT_PERE, POL_QUEUE_ID)
    SELECT TOP (100000)
        CAST(CTR.ID_CONTRAT AS INT),
        CAST(src.POL_OPERATION_ID AS INT),
        CAST(CASE WHEN src.POL_OPERATION_PID = 0 THEN NULL ELSE src.POL_OPERATION_PID END AS INT),
        CAST(src.POL_QUEUE_ID AS INT)
    FROM TFT.dbo.TFT_K_POLICY_OPERATIONS src
    INNER JOIN IC.dbo.ODS_CONTRATS_DAV CTR
        ON CTR.REFERENCE_EXTERNE_KELIA = src.POLICY_ID
        AND CTR.SOURCE = 2
        AND src.ARCHIVED <> 2
    LEFT JOIN IC.dbo.ODS_MOUVEMENTS_PERE omp   -- LEFT JOIN remplace NOT IN
        ON omp.N_MOUVEMENT = src.POL_OPERATION_ID
    WHERE omp.N_MOUVEMENT IS NULL;             -- IS NULL remplace NOT IN

    IF @@ROWCOUNT < 100000 BREAK;              -- sortie correcte
END;
';
