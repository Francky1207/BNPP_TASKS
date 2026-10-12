# Prompt Claude Code : Sprint 0 et 1 (à coller tel quel)

```
SPRINT 0/1 : socle du nouveau dépôt DoctoZen (monolithe modulaire .NET 8, PostgreSQL, Redis)

Lis d'abord D:\ENTREPRISE FAMILIALE\PROJETS\PROJET DOCTOZEN\_DIAGNOSTIC\ (SPECS_REFERENCE.md, DIAGNOSTIC.md). Les décisions ci-dessous priment : SGBD = PostgreSQL 16 (pas SQL Server).
Contexte : un seul développeur .NET (C#, MVC Razor, JS, EF Core), pas de maîtrise de Docker/React/Tailwind : explique brièvement tout choix technique non évident. Code orienté performance et réutilisabilité, clean architecture.

1. NOUVEAU dépôt Git sans l'historique des anciens. Aucun secret copié : user-secrets en local, variables d'environnement sur le VPS. .gitignore + gitleaks en CI. (Les secrets de l'ancien code sont à révoquer par Franck : ne les recopie jamais.)
2. Structure : une solution, src/DoctoZen.Web (hôte ASP.NET Core MVC Razor + /api/v1), src/Modules/<Nom>/{Domain,Application,Infrastructure,Contracts,Web}, src/BuildingBlocks, tests/, deploy/. Modules de départ : Identity, MedicalRecord. Inclure Directory et Assistant en squelette.
3. Base : PostgreSQL 16 via Npgsql + EF Core 8. Un schéma par module, un DbContext par module, migrations par module, snake_case, dates en UTC, aucune FK entre schémas. docker-compose.yml de dev (PostgreSQL + Redis) avec un script run-dev.ps1 unique.
4. Redis : interface ICacheService dans BuildingBlocks, implémentation Redis + repli mémoire si Redis indisponible.
5. Porte le code d'Authentication et MedicalRecords dans cette structure (déplacer, ne pas réécrire), puis corrige : contrôle d'accès par propriétaire/relation de soin sur TOUS les endpoints, policies RBAC, endpoints de recherche patient et profil protégés, bug du message d'erreur de SurgerieService (et test divergent), remplacement de SSH.NET par un stockage de documents local chiffré derrière une interface IDocumentStorage.
6. UI : layout Razor mobile-first avec barre d'onglets en bas (mobile) et barre latérale (desktop), registre de menus par profil (patient, médecin, admin), thème bleu ciel #1565C0 et blanc, épuré, cibles tactiles >= 44 px, modules JS ES réutilisables (api-client, ui-kit, offline-queue).
7. PWA : manifest, service worker (cache du shell versionné, network-first pour les données), page hors ligne, indicateur réseau, IndexedDB pour la lecture hors ligne (préparée, branchée au sprint suivant).
8. Interface IAssistantService (implémentation vide) dans le module Assistant.
9. Tests : xUnit sur Identity et MedicalRecord, test d'architecture (NetArchTest : pas de références croisées entre modules), et un test prouvant qu'un utilisateur ne lit pas le dossier d'un autre. Testcontainers PostgreSQL pour l'intégration.
10. CI GitHub Actions (build, test, gitleaks) et deploy/deploy.ps1 inspiré de nova_deploy.ps1 (zip, scp, copie de sauvegarde, reload, retour arrière).
11. Seed cohérent (identité + DME), compte admin de dev, collection .http de tests de fumée.
12. Termine par un README d'intégration court : lancer, tester, comptes de test, ajouter un module. Pas d'autres documents d'explication.

Livre par petits commits. À la fin : résumé de 15 lignes maximum et liste de ce qui reste à faire.
```
