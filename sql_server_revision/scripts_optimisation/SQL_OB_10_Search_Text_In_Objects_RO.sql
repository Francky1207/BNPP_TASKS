/*
NOM: SQL_OB_10_Search_Text_In_Objects_RO.sql | CAT: 08-OBJETS | P1
TYPE: READ ONLY | PERMS: VIEW DEFINITION
OBJET: Chercher un texte dans tout le code SQL (procs, fonctions, vues, triggers)
       Utile pour retrouver ou un champ est utilise, ou une table est referencee
PARAM: @SearchText (ex: 'ODS_MOUVEMENTS_PERE', 'NOT IN', 'N_MOUVEMENT')
*/
SET NOCOUNT ON;
DECLARE @SearchText NVARCHAR(256) = 'NOT IN'; -- <- Texte a chercher

SELECT
    o.type_desc                             AS [Type objet],
    o.name                                  AS [Nom objet],
    o.create_date                           AS [Cree le],
    o.modify_date                           AS [Modifie le],
    m.definition                            AS [Code source complet]
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE m.definition LIKE '%' + @SearchText + '%'
ORDER BY o.type_desc, o.name;
