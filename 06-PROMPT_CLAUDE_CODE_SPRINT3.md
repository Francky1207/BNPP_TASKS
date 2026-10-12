# Prompt Claude Code : Sprint 3 (Directory, proches, administration) à coller tel quel

```
SPRINT 3 : module Directory (lieux d'exercice, établissements, proches) + administration + petits restes

Contexte : sprint 2 validé. Relis le README du dépôt et D:\ENTREPRISE FAMILIALE\PROJETS\PROJET DOCTOZEN\_DIAGNOSTIC\ (00-ETAT-DU-PROJET.md à jour, 01-SPECS_REFERENCE.md §4 règles métier et §6 M2). Mêmes règles : performance, réutilisabilité, clean architecture, petits commits, aucun contenu clinique en cache, politiques nommées uniquement, pas de nouveaux documents d'explication, explications courtes pour Docker/PostgreSQL. Tests unitaires + intégration pour chaque flux.

A. DIRECTORY : ÉTABLISSEMENTS ET LIEUX D'EXERCICE
1. Entité Établissement : type (clinique, cabinet, centre de santé, entreprise), nom, adresse, ville, quartier, téléphone, coordonnées GPS facultatives, statut (en attente, validé, suspendu). Créé par l'admin (ou proposé par un médecin et validé par l'admin).
2. Lieu d'exercice : lie un médecin à un établissement OU à « exercice libre » (adresse propre), avec modes de consultation (présentiel, téléconsultation). Règle : un compte médecin, N lieux ; au moins un lieu validé requis pour être visible et réservable ; le rattachement à un établissement est une demande validée par l'admin.
3. Annuaire des médecins : recherche par spécialité, ville, mode (présentiel/télé), avec pagination, recherche insensible aux accents (extension unaccent + index pg_trgm, que tu ajoutes aussi pour la recherche de patients). Fiche publique du médecin (nom, spécialités, lieux, structure affichée). Aucune donnée sensible exposée sans connexion. Cache autorisé uniquement pour les listes publiques non cliniques.
4. Référentiel des spécialités (seed), gérable par l'admin.

B. PROCHES
5. Un proche est un profil patient sans connexion propre (enfant, parent âgé), créé et géré par le titulaire du compte, avec son propre dossier médical. Le titulaire a accès complet au dossier du proche ; chaque accès est audité avec l'identité du titulaire. Lien de parentabilité/tutelle enregistré (relation, date de naissance, consentement du titulaire). Un proche majeur peut créer son propre compte et reprendre son dossier (transfert tracé).
6. Bascule de profil dans l'interface : « Moi / Proche X », visible dans la barre supérieure, qui change le contexte du dossier médical. Toute requête clinique vérifie que le titulaire a bien le droit sur le profil actif (test qui prouve qu'un titulaire n'accède pas au proche d'un autre).
7. Le patient peut gérer ses accès : voir quels médecins ont une relation de soin avec lui, en retirer un (révocation avec effet immédiat, auditée).

C. ADMINISTRATION (interface Razor mobile-first)
8. Tableau de bord admin : comptes (liste paginée, recherche, filtre par rôle/statut), suspension/réactivation avec motif (révocation de session déjà en place), établissements (création, validation, suspension), demandes de rattachement des médecins, spécialités. Chaque action est auditée. L'admin n'a toujours aucun accès au contenu clinique.
9. Journal d'audit consultable par l'admin (filtres par date, acteur, action) avec politique de conservation configurable (par défaut 5 ans pour les accès au dossier, 1 an pour le reste) et purge planifiée.

D. INTERFACE ET PWA
10. Menus par profil mis à jour : patient (Accueil, Mon dossier, Mes proches, Trouver un médecin, Compte), médecin (Accueil, Patients, Mes lieux, Compte), admin (Tableau de bord, Comptes, Établissements, Validation, Audit). Barre d'onglets en bas sur mobile.
11. Page « Trouver un médecin » inspirée des captures Doctolib/Maiia du dossier IMAGES : grande barre de recherche unique, filtres simples, cartes de médecins épurées. Pas de surcharge.
12. Icônes PNG pour l'installation sur iOS (apple-touch-icon 180 px) et icônes manifest 192/512 px générées proprement à partir du logo existant ou d'un monogramme bleu ciel provisoire.

E. QUALITÉ
13. Tests d'architecture inchangés et verts ; 0 avertissement ; 0 paquet vulnérable ; gitleaks propre sur tout l'historique avant chaque push.
14. Mets à jour le README d'intégration (nouveaux flux, comptes de test : un établissement, un médecin avec lieu validé, un titulaire avec 2 proches). Ne modifie pas 00-ETAT-DU-PROJET.md.
15. Si une règle ci-dessus entre en conflit avec le code existant ou la spec, ne devine pas : signale-le dans le résumé final et applique l'option la plus prudente pour la sécurité des données de santé.

Ne pousse rien sur GitHub sans que je te l'aie confirmé dans ce message ou dans la conversation. À la fin : résumé de 15 lignes maximum et liste de ce qui reste à faire.
```
