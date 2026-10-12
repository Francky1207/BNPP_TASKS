# Prompt Claude Code : chantier autonome (M4, M5, M7, M8, M6, sprint 5, M9, IA) à coller tel quel

À coller dans Claude Code (dossier du dépôt). Il remplace le prompt 09 (cahiers) : T0 l'inclut. Claude Code prépare le plan et le script de reprise automatique, puis s'arrête ; Franck lance ensuite `.\scripts\autopilot.ps1`.

```
CHANTIER AUTONOME LONGUE DURÉE (3 à 5 h, sans surveillance). Étape 1 : préparer l'infrastructure de reprise. Étape 2 : Franck lance le script.

Contexte : sprint 4 validé, 49+ commits locaux, rien poussé. Relis CLAUDE.md, README, docs/EXPLOITATION.md et le code. Décisions de Franck : visio = LiveKit auto-hébergé ; prix de consultation fixé par le médecin entre un minimum et un maximum paramétrés par l'admin ; commission plateforme configurable (valeur provisoire 10 %) ; paiement à la réservation, remboursement automatique si annulation dans le délai, versement au médecin quand la consultation est confirmée réalisée ; fournisseur de paiement réel et opérateur SMS réel pas encore choisis (interfaces + implémentation simulée) ; IA : seulement les points d'extension, aucun LLM branché.

ÉTAPE 1 (maintenant, puis tu t'arrêtes)
1. Crée la branche autopilot/2026-10-11 depuis l'état actuel ; tout le chantier se fait dessus (Franck fusionnera après revue).
2. Crée docs/autopilot/PLAN.md (le plan ci-dessous, avec cases à cocher), docs/autopilot/PROGRESS.md (tâche en cours, dernière tâche terminée, ligne « STATUT: EN COURS » qui devient « STATUT: TERMINE » à la fin) et docs/autopilot/BLOCKERS.md (problèmes non résolus et décisions prises par défaut, avec date).
3. Crée scripts/autopilot.ps1 (compatible Windows PowerShell 5.1) : boucle de reprise automatique.
   - Paramètres : -MaxHeures (défaut 6), -AttenteMinutes (défaut 20).
   - Empêche la mise en veille pendant l'exécution (SetThreadExecutionState via Add-Type), vérifie que Docker répond (docker info) sinon attend et réessaie.
   - À chaque itération : s'il y a des modifications non commitées, les commite sur la branche avec le message « wip: état interrompu » (rien ne se perd) ; puis lance une session NEUVE `claude -p` (pas de --continue : l'état vit dans les fichiers) avec le prompt de session ci-dessous, en mode non interactif ; journalise la sortie dans .autopilot-logs/ (à ajouter au .gitignore).
   - Permissions : liste blanche explicite (dotnet, git sauf push/reset --hard/clean, docker compose, npm/npx, gitleaks, lecture/édition de fichiers du dépôt, scripts du dépôt) ; interdits : git push, git reset --hard, git clean, suppression récursive hors du dépôt, docker system prune, docker volume prune/rm, FLUSHALL. Vérifie les noms et la syntaxe exacts des options avec `claude --help` et teste-les.
   - Limite d'utilisation : si la sortie ou le code retour indique une limite atteinte (usage limit, rate limit, reset), attendre (heure de reprise si elle est donnée, sinon -AttenteMinutes puis allonger jusqu'à 60 min) puis relancer automatiquement. Autre échec : attendre 5 min et relancer.
   - Arrêt : STATUT: TERMINE dans PROGRESS.md, ou durée dépassée, ou 3 itérations de suite sans nouveau commit (écrire la raison dans BLOCKERS.md).
   - Option -Essai : lance une session triviale (« réponds OK et écris la date dans .autopilot-logs/essai.txt ») pour vérifier que tout fonctionne. Exécute-la toi-même et corrige.
4. Prompt de session (stocké dans docs/autopilot/SESSION.md et passé par le script) : « Lis CLAUDE.md, docs/autopilot/PLAN.md, PROGRESS.md et BLOCKERS.md. Vérifie l'état du dépôt (git status, git log -5, dotnet build). Si un travail a été interrompu (commit wip), termine-le ou annule-le proprement. Reprends à la première tâche non cochée et avance autant que possible en respectant les règles du plan. Mets PROGRESS.md à jour après chaque tâche. »
5. Ajoute à CLAUDE.md : les règles du plan, la règle « cahier fonctionnel + EXPLOITATION.md à jour dans le même commit », et la mention de docs/autopilot/.
6. Commit, puis réponds seulement : « Prêt. Franck : lancez .\scripts\autopilot.ps1 ». Ne commence PAS les tâches du plan dans cette session.

RÈGLES DU PLAN (valables pour chaque session)
- Jamais de push, jamais de secret dans le code ou les logs, jamais d'opération destructrice (pas de reset --hard, pas de nettoyage de volumes Docker, pas de FLUSHALL ; supprimer des clés Redis uniquement par préfixe dz:).
- Robustesse avant volume : une tâche n'est cochée que si le code est écrit, les tests (unitaires, intégration, architecture) de la tâche passent, la suite complète est verte et gitleaks est propre. Commit local à chaque tâche terminée ; tag git autopilot/NN-nom à chaque module terminé (points de retour faciles). Ne jamais laisser la suite rouge dans un commit.
- Échec : 3 tentatives maximum par problème, puis noter dans BLOCKERS.md (symptôme, hypothèses, ce qui a été essayé), prendre l'option la plus prudente pour la sécurité des données de santé, et passer à la tâche suivante.
- Décision ambiguë : ne pas bloquer, choisir l'option la plus prudente et la consigner dans BLOCKERS.md (section « Décisions par défaut à valider »).
- Architecture inchangée : monolithe modulaire, un module par domaine (Scheduling, Teleconsult, Payments, Notifications, Prescriptions...), communication par Contracts uniquement, test d'architecture vert, politiques d'autorisation nommées, contrôle propriétaire/relation de soin/titulaire sur chaque endpoint, audit des actions sensibles sans contenu clinique, aucun contenu clinique en cache serveur, Cache-Control no-store sur les réponses cliniques, migrations par module (testées sur copie), idempotence sur toute écriture rejouable.
- Performance : index adaptés, pagination par clés, pas de N+1, projections, plans de requête vérifiés sur gros volumes pour les listes chaudes (rendez-vous, créneaux, notifications, paiements).
- UI : design system existant (mobile-first, 360 px, cibles >= 44 px, libellés français via le dictionnaire central, thème clair). Vérification visuelle automatisée (Playwright, 360 et 1280 px, pas de scroll horizontal) pour chaque nouvel écran.
- Documentation : à chaque module, cahier fonctionnel dans docs/cahiers (même plan que T0), docs/EXPLOITATION.md (nouveaux services, variables, ports, dépannage), smoke.http, données de démo cohérentes (seed Development seulement).

PLAN (dans cet ordre)
T0. Cahiers fonctionnels et routine quotidienne.
 - docs/cahiers/00-INDEX.md + un cahier par module existant (01 identité et comptes, 02 annuaire/établissements/proches, 03 dossier médical, 04 administration et audit, 05 transverse), pour un lecteur médecin non technicien : objectif ; acteurs et droits (tableau voir/créer/modifier/supprimer) ; fonctionnalités détaillées (champs exacts, formats, valeurs, validations, calculs avec valeurs de référence exactes, états) ; règles métier ; confidentialité et sécurité en langage simple ; 3 à 5 parcours types ; limites et « À venir » ; points numérotés à faire valider par le médecin. 00-INDEX : modules M1 à M9 avec statut, pourcentage, date, glossaire. Décris uniquement ce qui existe.
 - docs/EXPLOITATION.md : section « Routine quotidienne » en tête (démarrage après redémarrage : Docker Desktop puis .\run-dev.ps1 ; arrêt et remise à zéro des données de test ; travail avec Claude Code et /clear ; fin de journée) + section « Chantier autonome » (comment lancer, reprendre, lire PROGRESS et BLOCKERS, revenir à un tag).
T1. M4 Consultations et rendez-vous (module Scheduling).
 - Disponibilités du médecin par lieu d'exercice et par type (cabinet, téléconsultation) : récurrence hebdomadaire, durée de créneau configurable (défaut 30 min), exceptions et congés, horizon de réservation configurable.
 - Types de consultation avec tarif fixé par le médecin entre min et max définis par l'admin (paramètres administrables).
 - Recherche de créneaux (rapide, paginée), réservation ATOMIQUE et idempotente (deux réservations simultanées du même créneau : une seule réussit, test de concurrence), réservation pour soi ou pour un proche (bascule de profil), motif, consentement explicite du patient à l'accès du médecin à son dossier pour cette prise en charge (crée la relation de soin, révocable).
 - Cycle de vie : en attente, confirmé, en cours, terminé, annulé, absent, reprogrammé ; annulation et reprogrammation avec délai configurable ; règles de transition testées.
 - Agenda médecin (jour et semaine, mobile-first), liste « Mes rendez-vous » patient/titulaire, détail, compte rendu de consultation (écrit via les droits d'écriture existants du dossier), confirmation bilatérale que la consultation a eu lieu.
 - Sans temps réel obligatoire : rafraîchissement léger (polling raisonnable) ; SignalR seulement si simple et testé.
T2. M5 Téléconsultation (module Teleconsult, LiveKit auto-hébergé).
 - Principe à expliquer en 15 lignes dans docs/EXPLOITATION.md pour un développeur qui n'a jamais fait de visio : LiveKit est le serveur de médias ; l'application ne génère qu'un jeton signé (JWT) autorisant UNE personne à entrer dans UNE salle ; le navigateur se connecte directement à LiveKit avec ce jeton ; le TURN intégré traverse les pare-feux.
 - docker-compose de dev : service LiveKit (mode dev) ; clés via user-secrets / variables d'environnement, jamais dans le code. Prod : section « Déployer LiveKit sur le VPS » (ports, pare-feu, proxy inverse Nginx pour wss, certificat, TURN, variables, vérification).
 - Génération du jeton côté serveur : une salle par rendez-vous, seulement les deux participants autorisés (patient ou titulaire, médecin), fenêtre d'accès (10 min avant jusqu'à fin + 30 min), droits minimaux, durée courte, audit. Tests unitaires du jeton (claims, expiration, refus hors fenêtre ou hors participant).
 - Salle d'attente virtuelle, écran d'appel mobile-first (micro, caméra, raccrocher, bascule « audio seul », indicateur de qualité réseau), mode économique automatique si la connexion est mauvaise (audio seul proposé), reconnexion automatique, pas d'enregistrement, chat texte simple dans l'appel. Client JS LiveKit servi localement depuis wwwroot (pas de CDN), compatible CSP.
 - Passage du rendez-vous à « en cours » puis « terminé » ; confirmation bilatérale de consultation réalisée.
 - Test Playwright avec périphériques média simulés (deux navigateurs, un patient et un médecin dans la même salle) si LiveKit démarre dans Docker ; sinon tests de contrat et note dans BLOCKERS.md.
T3. M7 Paiement (module Payments).
 - Interface IPaymentGateway + implémentation simulée (Development uniquement, interdite en Production) ; webhooks signés et idempotents ; états : en attente, payé, échoué, remboursé ; réservation avec créneau retenu 10 minutes pendant le paiement.
 - Paiement à la réservation, remboursement automatique si annulation dans le délai, commission configurable (10 % provisoire), grand livre comptable immuable (écritures patient, plateforme, médecin), versement au médecin déclenché par la confirmation de consultation réalisée, reçu PDF (SkiaSharp, déjà présent), réconciliation périodique.
 - Pages : paiement mobile-first (choix opérateur Orange, MTN, Moov, Wave en simulation), historique patient, revenus du médecin, supervision admin des transactions. Aucun numéro de carte ou de compte stocké.
T4. M8 Notifications (module Notifications).
 - Boîte d'envoi transactionnelle (outbox) + tâche de fond idempotente ; canaux via ISmsSender, IEmailSender, notification dans l'application (cloche) ; Web Push (VAPID) si simple, sinon documenter.
 - Préférences par utilisateur ; rappels de rendez-vous (J-1, H-1), confirmation, annulation, paiement, rappels de vaccins en retard ; limitation de débit ; aucun contenu clinique dans les SMS et e-mails (jamais de diagnostic).
T5. M6 Ordonnances (module Prescriptions).
 - Ordonnance rédigée par le médecin pendant ou après une consultation (lignes : médicament en texte libre pour l'instant, posologie, durée, remarques), signature numérique, PDF serveur (SkiaSharp), QR code signé et page publique de vérification minimale (validité, prescripteur, date ; jamais l'identité du patient), expiration, limitation de débit, audit.
 - Visible par le patient/titulaire, téléchargeable, lien avec la rubrique traitements. Base médicamenteuse : à venir (interface de recherche prévue).
T6. Reste du sprint 5.
 - Bris de glace : médecin validé, motif obligatoire, 2 h, lecture seule, audit renforcé, notification au patient, revue par l'admin.
 - Export RGPD du dossier (JSON et PDF), sur demande du patient/titulaire, audité, fichier chiffré à durée de vie courte.
 - Lecture hors ligne du dossier (opt-in, IndexedDB chiffré, purge à la déconnexion, jamais d'écriture hors ligne sur le clinique) ; file de synchronisation avec idempotence pour les actions non cliniques sûres.
 - Dépôt de résultats par le patient dans une section « déclaré par le patient ».
T7. M9 Back-office.
 - Tableau de bord admin (KPI : inscriptions, médecins validés, rendez-vous, consultations, revenus, commissions), paramètres (bornes de tarifs, commission, délais, durées de créneau), supervision des transactions, modification d'un établissement, gestion des référentiels (spécialités, vaccins, catégories), export CSV des journaux d'audit. Aucune donnée clinique pour l'admin.
T8. Préparation IA (points d'extension seulement).
 - Dans le module Assistant : gestion du consentement IA (table, révocable, par utilisateur), service d'anonymisation/pseudonymisation avant tout appel externe (retire noms, téléphones, e-mails, dates exactes, identifiants), journal d'audit des appels IA, interface IAssistantService complétée, squelette du pipeline (règles puis LLM puis carte de validation avant toute action), interrupteur de fonctionnalité désactivé par défaut, tests de l'anonymiseur. Aucun fournisseur LLM branché, aucun appel réseau. Cahier fonctionnel « Assistant » avec ce qui est prévu.
T9. Consolidation.
 - Suite complète 3 fois de suite verte, 0 avertissement, 0 paquet vulnérable, gitleaks sur tout l'historique, revue de sécurité des nouveaux endpoints (autorisation, audit, cache, no-store), migrations rejouées sur copie de la base de dev, cahiers et 00-INDEX à jour, smoke.http, seed de démo complet.
 - Écris docs/autopilot/RAPPORT.md (40 lignes maximum) : ce qui est fait par module avec % d'avancement, tags git, décisions par défaut à valider, blocages, ce que Franck doit tester sur un vrai téléphone, questions pour le médecin. Mets « STATUT: TERMINE » dans PROGRESS.md.
```
