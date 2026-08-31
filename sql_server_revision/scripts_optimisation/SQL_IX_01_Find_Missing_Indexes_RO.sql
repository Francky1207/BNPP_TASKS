/*
============================================================
NOM          : SQL_IX_01_Find_Missing_Indexes_RO.sql
CATEGORIE    : 04 - INDEX ET STATISTIQUES
PRIORITE     : P0
AUTEUR       : Investigation Toolkit — SEEDKA HOLDING
VERSION      : 1.0 — Calibré SQL Server 2019
============================================================

OBJECTIF :
  Identifier les index manquants les plus impactants, suggérés
  par SQL Server lui-même en analysant les plans d'exécution
  depuis le dernier redémarrage du serveur.

  CONTEXTE DIRECT : L'index manquant sur ODS_MOUVEMENTS_PERE.N_MOUVEMENT
  détecté le 28/08/2026 aurait pu être identifié par ce script AVANT
  que le problème ne dure 20h.

TYPE        : READ ONLY
RISQUE      : FAIBLE — lecture de DMV, aucune modification

PERMISSIONS : VIEW SERVER STATE

PARAMETRES :
  @ImpactMinimum    — impact minimum % (défaut: 50 — suggère les plus critiques)
  @BaseCible        — filtrer sur une base ('' = toutes, 'IC' = seulement IC)
  @TopN             — nb d'index à afficher (défaut: 30)

UTILISATION :
  -- Voir les 30 index les plus impactants sur toutes les bases
  @TopN = 30, @ImpactMinimum = 50

  -- Voir uniquement les suggestions sur la base IC
  @BaseCible = 'IC'

RÉSULTATS :
  - Impact estimé (0-100%) — le plus impactant = priorité 1
  - Table concernée
  - Colonnes suggérées (equality = dans WHERE avec =, inequality = avec </>)
  - Colonnes INCLUDE suggérées (pour couvrir le SELECT)
  - Script CREATE INDEX prêt à l'emploi (à valider avant exécution)

INTERPRÉTATION :
  avg_user_impact > 90%  → Index CRITIQUE — forte amélioration attendue
  avg_user_impact 70-90% → Index important
  avg_user_impact < 50%  → Index utile mais moins prioritaire

  ⚠️ ATTENTION — Ne pas créer tous les index suggérés aveuglément :
  → Vérifier s'il n'existe pas déjà un index similaire (SQL_IX_02)
  → Vérifier si la table est très écrite (index = coût sur INSERT/UPDATE)
  → Prioriser par avg_user_impact ET seek_count (fréquence d'usage)

VALIDATION AVANT CRÉATION :
  1. Vérifier les index existants : SQL_IX_02_List_Table_Indexes_RO.sql
  2. Vérifier les doublons : SQL_IX_06_Find_Duplicate_Indexes_RO.sql
  3. Tester le CREATE INDEX en DEV/RECETTE avant PROD

ETAPE SUIVANTE :
  Après création d'un index → SQL_CM_04_Compare_Index_Usage_Before_After_RO.sql
============================================================
*/

SET NOCOUNT ON;

-- ============================================================
-- PARAMÈTRES
-- ============================================================
DECLARE @ImpactMinimum    DECIMAL(5,2)  = 50.0;   -- % impact minimum
DECLARE @BaseCible        NVARCHAR(128) = '';      -- '' = toutes
DECLARE @TopN             INT           = 30;

PRINT '================================================================';
PRINT 'SQL_IX_01 — INDEX MANQUANTS — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT 'Impact minimum : ' + CAST(@ImpactMinimum AS VARCHAR) + '%';
PRINT 'Base filtrée   : ' + CASE WHEN @BaseCible = '' THEN '(toutes)' ELSE @BaseCible END;
PRINT '⚠️  Ces suggestions sont des pistes — valider avant application';
PRINT '================================================================';

-- ============================================================
-- INDEX MANQUANTS SUGGÉRÉS PAR SQL SERVER
-- ============================================================

SELECT TOP (@TopN)
    migs.avg_user_impact                                    AS [Impact moyen (%)],
    migs.user_seeks                                         AS [Nb seeks (fréquence)],
    migs.user_scans                                         AS [Nb scans],
    CAST(migs.user_seeks * migs.avg_user_impact AS INT)     AS [Score priorité (seeks×impact)],
    DB_NAME(mid.database_id)                                AS [Base],
    mid.statement                                           AS [Chemin table complet],
    mid.equality_columns                                    AS [Colonnes égalité (WHERE col=)],
    mid.inequality_columns                                  AS [Colonnes inégalité (WHERE col>)],
    mid.included_columns                                    AS [Colonnes INCLUDE (SELECT)],

    -- Script CREATE INDEX prêt à l'emploi
    'CREATE NONCLUSTERED INDEX [IX_' +
        OBJECT_NAME(mid.object_id, mid.database_id) + '_' +
        REPLACE(REPLACE(ISNULL(mid.equality_columns, '') +
            ISNULL('_' + mid.inequality_columns, ''), '[', ''), ']', '') + ']' +
    ' ON ' + mid.statement +
    ' (' + ISNULL(mid.equality_columns, '') +
        CASE WHEN mid.inequality_columns IS NOT NULL
             AND mid.equality_columns IS NOT NULL
             THEN ', ' ELSE '' END +
        ISNULL(mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') +
    ' WITH (ONLINE = ON);'                                  AS [Script CREATE INDEX à valider],

    -- Contexte du dernier seek (quand a été identifié ce besoin ?)
    migs.last_user_seek                                     AS [Dernier seek détecté],
    migs.last_user_scan                                     AS [Dernier scan détecté],

    -- Signal de priorité
    CASE
        WHEN migs.avg_user_impact > 90
        THEN '🔴 CRITIQUE — impact très élevé'
        WHEN migs.avg_user_impact > 70
        THEN '🟡 IMPORTANT — à traiter rapidement'
        WHEN migs.avg_user_impact > 50
        THEN '🟢 UTILE — à planifier'
        ELSE 'INFO'
    END                                                     AS [Priorité]

FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig
    ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs
    ON migs.group_handle = mig.index_group_handle
WHERE migs.avg_user_impact >= @ImpactMinimum
  AND (
    @BaseCible = ''
    OR DB_NAME(mid.database_id) = @BaseCible
  )
ORDER BY (migs.user_seeks * migs.avg_user_impact) DESC;   -- tri par score priorité

-- ============================================================
-- EXEMPLE CONCRET : L'INDEX QUI AURAIT RÉSOLU LE 28/08/2026
-- ============================================================
PRINT '';
PRINT '================================================================';
PRINT 'EXEMPLE CONCRET (cas du 28/08/2026 — NOT IN sur ODS_MOUVEMENTS_PERE)';
PRINT '================================================================';
PRINT '';
PRINT 'L''index suivant aurait permis au LEFT JOIN de remplacer le NOT IN';
PRINT 'avec des performances O(n) au lieu de O(n²) :';
PRINT '';
PRINT '-- Vérifier d''abord s''il existe :';
PRINT 'SELECT * FROM IC.sys.indexes WHERE object_id = OBJECT_ID(''IC.dbo.ODS_MOUVEMENTS_PERE'')';
PRINT '  AND name LIKE ''%N_MOUVEMENT%'';';
PRINT '';
PRINT '-- Si absent, le créer (en RECETTE d''abord) :';
PRINT 'CREATE NONCLUSTERED INDEX [IX_ODS_MOUVEMENTS_PERE_N_MOUVEMENT]';
PRINT '    ON IC.dbo.ODS_MOUVEMENTS_PERE (N_MOUVEMENT)';
PRINT '    WITH (ONLINE = ON);   -- ONLINE = pas de blocage en prod';
PRINT '';
PRINT '================================================================';
PRINT 'FIN SQL_IX_01 — ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT 'Valider avec SQL_IX_02 avant tout CREATE INDEX en production';
PRINT '================================================================';
