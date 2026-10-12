# Prompt Claude Code : cahiers fonctionnels par module (à coller tel quel)

```
CAHIERS FONCTIONNELS PAR MODULE (documentation métier pour le médecin partenaire), petits commits, rien poussé.

Objectif : décrire fidèlement ce que l'application fait AUJOURD'HUI, module par module, pour un lecteur médecin non technicien (aucun jargon de code, aucun nom de classe ou de table). Lis le code réel : ne décris que ce qui existe ; ce qui n'existe pas est marqué « À venir ». N'invente rien.

Fichiers : docs/cahiers/00-INDEX.md puis un fichier par module : 01-identite-et-comptes.md, 02-annuaire-etablissements-proches.md, 03-dossier-medical.md, 04-administration-et-audit.md, 05-transverse.md (mobile/PWA et hors ligne, notifications, sécurité, audit). En français, phrases courtes, titres clairs.

Structure de chaque cahier :
1. Objectif du module (3 lignes).
2. Acteurs et droits : tableau « qui peut voir / créer / modifier / supprimer quoi » (patient, titulaire pour un proche, médecin avec relation de soin, médecin sans relation, administrateur).
3. Fonctionnalités détaillées, une sous-section par écran ou rubrique : à quoi ça sert, champs (nom, obligatoire ou non, format, longueur, valeurs possibles en français), règles de validation et messages, calculs automatiques (IMC, vaccins dus ou en retard par âge et sexe, plages de référence des paramètres vitaux : donne les valeurs exactes utilisées), états et cycles de vie (ex. demande de validation d'un médecin : en attente, approuvée, refusée), ce que voit chaque profil.
4. Règles métier (visibilité d'un médecin dans l'annuaire, proches, reprise de dossier, droits d'écriture, suppression logique, historique des versions...).
5. Confidentialité et sécurité, en langage simple : qui peut accéder, durée, journalisation, chiffrement, ce que contient (et ne contient pas) le journal d'audit.
6. Parcours types pas à pas (3 à 5 scénarios réalistes, ex. « Un médecin ajoute une tension artérielle au dossier d'un patient qui l'a autorisé »).
7. Limites actuelles et « À venir ».
8. Points à faire valider par le médecin : liste numérotée de questions précises (calendrier vaccinal, plages de référence, liste des affections et catégories CIM-10 retenues, vocabulaire des rubriques, rubriques manquantes, règles d'accès, durée de conservation).

00-INDEX.md : tableau des modules prévus au cahier des charges (M1 à M9 de 01-SPECS_REFERENCE) avec statut (fait, partiel, à venir), pourcentage estimé, lien vers le cahier, date de mise à jour ; glossaire des termes (relation de soin, bris de glace, titulaire, proche, suppression logique...).

Le cahier 03 est le plus détaillé : une sous-section par rubrique (informations administratives, contacts d'urgence, allergies, antécédents médicaux, antécédents familiaux, gynéco-obstétricaux, mode de vie, traitements réguliers, paramètres vitaux, vaccinations, chirurgies, documents, chronologie), avec les champs exacts.

RÈGLE DE MAINTIEN (à ajouter à CLAUDE.md) : tout changement fonctionnel met à jour le cahier du module concerné dans le même commit (et la date dans 00-INDEX.md) ; tout nouveau module livre son cahier avec le même plan ; les points à faire valider sont conservés jusqu'à validation par le médecin.

À la fin : résumé de 8 lignes maximum.


Ajoute à docs/EXPLOITATION.md une section « Routine quotidienne » en tête de fichier (10 lignes maximum par cas, commandes exactes pour Windows PowerShell 5.1) :
1. Démarrer la journée après un redémarrage du PC : lancer Docker Desktop, attendre « Engine running », puis cd vers le dépôt et .\run-dev.ps1, puis l'adresse à ouvrir.
2. Arrêter proprement (Ctrl+C, et si besoin docker compose stop), et remettre les données de test à zéro (docker compose down -v puis .\run-dev.ps1).
3. Travailler avec Claude Code : ouvrir une session dans le dépôt (cd puis claude), reprendre après un redémarrage, quand utiliser /clear (début d'un nouveau sprint), où est le contexte du projet (CLAUDE.md, README, docs/).
4. Avant chaque fin de journée : git status, git log -5, rien à pousser sans accord.
Ajoute une ligne au journal des changements. Commit.
```
