-- ============================================================
-- Jeu de donnees de test pour SQL Server
-- A executer dans une base de developpement (PAS en production)
-- ============================================================

IF OBJECT_ID('dbo.Staging_Clients', 'U') IS NOT NULL DROP TABLE dbo.Staging_Clients;
GO
CREATE TABLE dbo.Staging_Clients (
    CODE_CLIENT     VARCHAR(20)   NOT NULL,
    RAISON_SOCIALE  VARCHAR(200)  NULL,
    VILLE           VARCHAR(100)  NULL,
    REGION          VARCHAR(100)  NULL,
    MONTANT         DECIMAL(18,2) NULL,
    DATE_CREATION   DATE          NULL,
    STATUT          VARCHAR(20)   NULL,
    DATE_CHARGEMENT DATETIME      DEFAULT GETDATE()
);
GO

-- Table de controle : sert a tester Invoke-SqlQuery et Get-SqlTableSchema
IF OBJECT_ID('dbo.Ref_Produits', 'U') IS NOT NULL DROP TABLE dbo.Ref_Produits;
GO
CREATE TABLE dbo.Ref_Produits (
    CODE_PRODUIT    VARCHAR(20)  NOT NULL PRIMARY KEY,
    LIBELLE         VARCHAR(200) NULL,
    FAMILLE         VARCHAR(100) NULL,
    PRIX_CATALOGUE  DECIMAL(18,2) NULL
);
GO

INSERT INTO dbo.Ref_Produits (CODE_PRODUIT, LIBELLE, FAMILLE, PRIX_CATALOGUE) VALUES
('PRD001', 'Produit 1', 'Assurance Vie', 49.90),
('PRD002', 'Produit 2', 'Prevoyance',    99.80),
('PRD003', 'Produit 3', 'Retraite',     149.70),
('PRD004', 'Produit 4', 'Sante',        199.60);
GO

-- Requetes de controle de coherence (usage quotidien type)
-- 1. Doublons sur la cle
SELECT CODE_CLIENT, COUNT(*) AS NB
FROM dbo.Staging_Clients GROUP BY CODE_CLIENT HAVING COUNT(*) > 1;

-- 2. Valeurs orphelines (pas de correspondance dans le referentiel)
SELECT DISTINCT v.CODE_PRODUIT
FROM dbo.Staging_Ventes v
LEFT JOIN dbo.Ref_Produits p ON p.CODE_PRODUIT = v.CODE_PRODUIT
WHERE p.CODE_PRODUIT IS NULL;

-- 3. Taux de remplissage par colonne
SELECT COUNT(*) AS TOTAL,
       SUM(CASE WHEN RAISON_SOCIALE IS NULL THEN 1 ELSE 0 END) AS RS_VIDES,
       SUM(CASE WHEN MONTANT IS NULL THEN 1 ELSE 0 END)        AS MT_VIDES
FROM dbo.Staging_Clients;