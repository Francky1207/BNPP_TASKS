# DoctoZen : état du projet et index (mis à jour le 10/10/2026, après le sprint 4)

**Lire ce fichier en premier.** Il remplace toute information contraire dans les anciens documents.

## Mission
Plateforme e-santé (téléconsultation, RDV, carnet de santé, ordonnances, paiement Mobile Money) pour la Côte d'Ivoire puis l'Afrique de l'Ouest. Développeur unique : Franck (.NET). Contexte réseau 2G/3G : hors ligne et faible débit obligatoires.

## Décisions en vigueur
- Monolithe modulaire .NET 8, nouveau dépôt unique ; microservices écartés.
- PostgreSQL 16 (un schéma par module) + Redis ; nouveau VPS dédié.
- Front Razor serveur + modules JS + PWA mobile-first ; Blazor Server exclu ; thème bleu ciel et blanc (#1565C0 texte/boutons, #E3F2FD fonds, #4FC3F7 accents, variables CSS).
- Interface unique avec menus par profil (patient, médecin, admin, ...).
- IA : `IAssistantService` dès le socle ; pipeline NOVA (règles, puis LLM, puis carte de validation).
- Aucun contenu clinique dans le cache serveur (liste blanche de clés) ; politiques d'autorisation nommées uniquement (jamais `Roles=`).
- Détail : `03-ARCHITECTURE_CIBLE.md`.

## Avancement réel
- Diagnostic initial (09/10/2026) : MVP ≈ 15 %.
- **Sprint 0/1 validé (09/10)** : socle, PostgreSQL, accès au dossier par relation de soin avec audit, chiffrement AES-256-GCM, interface mobile-first, PWA, CI.
- **Sprint 2 validé (10/10)** : Identity complet (inscription téléphone/e-mail, OTP, 2FA, verrouillage, validation des médecins), sécurité des sessions et du cache.
- **Sprint 3 validé (10/10)** : annuaire « Trouver un médecin » public (recherche sans accents), lieux d'exercice et établissements, proches avec bascule « Moi / Proche » et reprise par un proche majeur, administration (comptes, établissements, rattachements, spécialités), journal d'audit consultable avec conservation configurable (5 ans accès au dossier, 1 an le reste), icônes PNG.
- **Affinage UI + guide d'exploitation (10/10)** : design system (texte 15 px, cartes à relief, icônes SVG uniformes, thème clair forcé), `docs/EXPLOITATION.md` (guide évolutif, mis à jour par Claude Code à chaque changement d'exploitation, règle dans `CLAUDE.md`), Redis Docker centralisé sur 6379 (préfixe `dz:`, `restart: unless-stopped`), scripts compatibles PowerShell 5.1.
- **Sprint 4 validé (10/10)** : dossier médical en 12 rubriques, droits d'écriture (médecin avec relation de soin = rubriques cliniques ; patient/titulaire = rubriques déclaratives ; admin = aucun accès), source et date sur chaque entrée, historique chiffré des versions, suppression logique, audit sans contenu clinique, vaccins dus/en retard par âge et sexe (calendrier PEV de démonstration), paramètres vitaux avec alertes et graphique, documents (type réel vérifié, chiffrés, aperçu), timeline paginée, réponses cliniques `no-store`, libellés français centralisés, notifications admin (lieu validé/refusé, reprise de dossier). Test intermittent corrigé (cause : chiffreur global partagé entre hôtes de test).
- État du dépôt local `C:\Users\aurel\source\repos\DoctoZen` : 49 commits, 270 tests verts (suite passée 10 fois de suite), 0 avertissement, 0 paquet vulnérable, gitleaks propre. `origin` configuré, **rien poussé**. Migration du sprint 4 non réversible (retour arrière = restauration de sauvegarde), testée sur une copie de la base de dev.
- Vérification visuelle : faite en navigateur automatisé (20 écrans, 360 px et desktop) et par Franck sur Chrome en émulation mobile (accueil, dossier, proches, annuaire validés). **Pas encore de test sur vrai téléphone.**
- Avancement approximatif : Identity ≈ 90 %, Directory ≈ 75 %, Administration ≈ 65 %, Dossier médical ≈ 85 % (restent export, bris de glace, lecture hors ligne), le reste 0 %.
- Comptes de dev : patient1..5@, dr.kouame@ (lieu validé, Clinique Les Palmiers), dr.diallo@, admin@doctozen.local (mot de passe de dev uniquement, jamais en production). patient1 a 2 proches.

## Règles métier retenues
- **Visibilité d'un médecin dans l'annuaire** : validé (ONMCI), actif, avec au moins un lieu approuvé par l'admin dans un établissement validé (ou « exercice libre » approuvé par l'admin). Suspendre un établissement masque ses médecins. L'accès clinique d'un médecin reste contrôlé par sa validation ONMCI et la relation de soin, indépendamment de la visibilité.
- **Proches** : profil patient sans connexion propre, créé par un titulaire qui atteste le lien. Le titulaire a les mêmes droits que sur son propre dossier (lecture + gestion des accès des médecins, pas d'écriture clinique), chaque accès est audité au nom du titulaire. Reprise par un proche majeur : code à usage unique valable 7 jours, le dossier passe sur son compte, le titulaire perd l'accès ; refus si le compte a déjà un dossier (pas de fusion automatique).
- **Audit** : les patients n'y apparaissent que par un identifiant court (un journal d'accès peut révéler de l'information de santé).
- **Autoriser un médecin** : la recherche passe par l'annuaire public, donc seuls les médecins avec un lieu validé sont autorisables depuis la page « Accès au dossier ».
- **Bris de glace** (à implémenter) : médecin validé, motif obligatoire, accès limité à 2 h, lecture seule, audit renforcé, notification au patient, revue par l'admin.
- **Qui écrit dans le dossier** (implémenté au sprint 4 ; documents déposés par le médecin seulement ; le médecin n'écrit pas les rubriques déclaratives) : le médecin avec relation de soin écrit les rubriques cliniques ; le patient/titulaire renseigne les rubriques déclaratives (infos administratives, contacts d'urgence, mode de vie, antécédents familiaux) marquées « déclaré par le patient ».

## Choix sprint 4 confirmés (10/10)
- Documents : dépôt par le médecin uniquement pour l'instant ; dépôt de résultats par le patient (section « déclaré par le patient ») à prévoir plus tard.
- Tarif de consultation absent de l'annuaire (arrivera avec les tarifs réglementés, module paiement).
- Série vaccinale interrompue : reste signalée en retard au-delà de l'âge maximum, le médecin décide du rattrapage.
- Calendrier vaccinal (PEV Côte d'Ivoire) et plages de référence des paramètres vitaux : **valeurs de démonstration à faire valider par un médecin référent avant tout pilote**.
- Rubrique gynéco-obstétricale visible pour les femmes ou sexe non renseigné.

## Points ouverts (par priorité)
1. Premier push GitHub : à autoriser par Franck (dire « pousse » à Claude Code) ; dépôt `DOCTOZEN` à vérifier en privé.
2. Révocation des secrets : jeton GitHub et dépôts en privé faits ; clé JWT sans objet (jamais déployée) ; restent à faire : mot de passe d'application Gmail, mot de passe `sa` SQL Server, serveur SFTP du port 2222 (arrêter ou changer le mot de passe), vérification des redirections de ports de la box.
3. Vérification visuelle sur navigateur et téléphone (iOS : installation PWA, bascule de profil sur petit écran, performance 3G).
4. À faire côté admin : afficher les lieux déclarés sur la page de validation des médecins ; notifications SMS/e-mail (lieu validé ou refusé, reprise de dossier) ; modification d'un établissement ; carte GPS.
5. Fournisseur SMS réel ; changement de numéro par OTP ; chiffrement au repos des clés Data Protection sur le VPS (au sprint de déploiement).
6. Suppression des données (droit à l'effacement) : durée légale de conservation d'un dossier médical à confirmer pour la Côte d'Ivoire avant de spécifier.

## Prochaine action
1. Franck : réinitialiser la base de dev (nouvelles données de démo), vérifier le dossier médical sur Chrome mobile, terminer les secrets restants, dire « pousse » à Claude Code.
2. Test sur vrai téléphone (Android et iPhone, réseau lent, zone sûre iOS, appareil photo, PDF, icône PWA, page hors ligne).
3. Sprint 5 : export RGPD (JSON/PDF), bris de glace, lecture hors ligne du dossier. Puis sprints 6-7 rendez-vous, selon `03-ARCHITECTURE_CIBLE.md`.

## Index des documents du projet
| Fichier | Contenu |
|---|---|
| `00-ETAT-DU-PROJET.md` | Ce fichier |
| `01-SPECS_REFERENCE.md` | **Seule version qui fait foi** des specs (périmètre, règles métier, modules, manques) |
| `02-DIAGNOSTIC_09-10-2026.md` | Constat de l'existant : code, build, tests, sécurité, UI, NOVA |
| `03-ARCHITECTURE_CIBLE.md` | Décisions d'architecture, structure, plan de reprise |
| `04-PROMPT_CLAUDE_CODE_SPRINT0.md` | Prompt du sprint 0/1 (exécuté) |
| `05-PROMPT_CLAUDE_CODE_SPRINT2.md` | Prompt du sprint 2 (exécuté) |
| `06-PROMPT_CLAUDE_CODE_SPRINT3.md` | Prompt du sprint 3 (exécuté) |
| `07-PROMPT_CLAUDE_CODE_SPRINT4.md` | Prompt du sprint 4 (dossier médical, exécuté) |
| `08-PROMPT_CLAUDE_CODE_UI_ET_EXPLOITATION.md` | Prompt affinage UI + guide d'exploitation (exécuté) |
| `1- CAHIER_DES_CHARGES_DEFINITIF`, `2- LISTE COMPLETE DES MODULES`, `0- ANALYSE FINANCIERE` | Documents sources métier conservés |
| `IMAGE 1-13` | Captures Doctolib (1-3) et Maiia (4-13) pour l'inspiration mobile |

## Questions ouvertes à trancher (priorité décroissante)
Preuve de consultation réalisée ; périmètre hors ligne détaillé ; agrégateur de paiement et opérateur SMS ; choix de la visio ; cadre IA (consentement, fournisseur) ; durée légale de conservation des dossiers.
