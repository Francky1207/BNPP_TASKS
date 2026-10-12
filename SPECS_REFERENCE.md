# DoctoZen : spécifications de référence

> Version consolidée du 09/10/2026, issue du diagnostic. **Ce document remplace tous les autres pour le périmètre et les priorités.** Le détail des cas d'utilisation reste dans les fichiers UC cités (ils font foi pour le détail).
> Légende des statuts : **UC** = use case écrit · **SPEC** = listé/décrit sans UC · **CONTRA** = sources contradictoires (arbitrage ci-dessous) · **MANQ** = à spécifier.

---

## 1. Documents qui font foi

| Sujet | Document de référence | Justification |
|---|---|---|
| Vision, périmètre fonctionnel, exigences | `ARCHITECTURE PROJET/1- CAHIER_DES_CHARGES_DEFINITIF - 20250924.docx` (modifié le 16/01/2026) | Copie la plus récente ; seule à détailler le DME (constantes, chirurgies, antécédents familiaux). La copie `DEFINITIF/` est antérieure. |
| Découpage en modules techniques | `ARCHITECTURE PROJET/2- LISTE COMPLETE DES MODULES` | Texte identique à celui de `DEFINITIF/` ; 26 modules. |
| Ordre et statut des modules, règles transversales | `ARCHITECTURE PROJET/DoctoZen_Roadmap_Technique.docx` (avril 2026) | Plus récent que la roadmap Scrum (déc. 2025). **Corrigé par ce document** (front, ports, statuts). |
| Dossier médical (DME) : détail | `PREPARATION_DEV_EQUIPE/Module Medical Records/*` (5 fichiers .md, 01/2026) + `AMLIORATIONS_DOCTOZEN_CLIENT_20260606.pdf` | Seuls UC du DME ; le PDF du 06/06 remplace le DOCX du 26/04 (même contenu, plus récent). |
| Consultation : détail | `PREPARATION_DEV_EQUIPE/Module Consultation/*` (2 fichiers .md, 27/07/2026) | Documents les plus récents du dossier. |
| Règles métier médecin/structure/tarification | `Observations_20260426.md` + grille tarifaire (`2- PitchDeck`, `Questions Recueil Besoins/4-…png`) | Décisions postérieures au CDC, absentes de celui-ci. |
| Plan d'action en cours | `TAF_CEDRIC_BRICE_20260607.docx` | Dernier arbitrage connu (juin 2026). |
| Maquette fonctionnelle (écrans) | `3- MAQUETTE APPLICATION TELECONSULTATION.docx` + `IMAGES/` (Doctolib, Maiia) | Seule maquette existante. |

**Obsolètes ou doublons, à archiver** : `DEFINITIF/*` (doublons), `4- UNE APPLICATION…docx` et `CAHIER_DE_CHARGES.txt` (pré-CDC), `MAQUETTE.txt`, `Business Plan.txt`, `3- ROADMAP MODULAIRE ET PLAN SCRUM`, `DoctoZen_Roadmap_Technique_Ancienne_Version.docx` (en réalité un fichier Markdown), `4- Architecture Technique .NET.cs`, `5- PROMPT COMPLET….cs`, `architecture-globale.md`, `13-setup-sprint3-for-developpers.md`, gabarits `CONFIGURATION TECHNIQUE/*`. Détail dans `INVENTAIRE.csv`.

---

## 2. Arbitrages des contradictions

| # | Contradiction | Sources | Décision de référence |
|---|---|---|---|
| C1 | Technologie du front : MVC Razor / Blazor Server / Blazor WASM / React | Roadmap tech (MVC), architecture-globale + UC Consultation (Blazor greffé sur MR), Archi .NET (Blazor puis WASM), setup sprint 3 (React) | **Une seule UI Razor côté serveur, mobile-first, en PWA** (voir DIAGNOSTIC §5). Blazor Server ne fonctionne pas hors ligne (connexion SignalR permanente), ce qui contredit l'exigence « hors ligne essentiel ». |
| C2 | Architecture : microservices (CDC §5, Archi .NET, K8s, Istio) vs ressources réelles (1 développeur, 1 VPS) | CDC, Archi .NET | **Monolithe modulaire .NET 8**, un module par domaine, une base avec un schéma par module. Microservices écartés tant que la charge ne l'exige pas. |
| C3 | SGBD : PostgreSQL 16 (Archi .NET, ancienne roadmap) vs SQL Server (code) | Archi .NET / code | **SQL Server** (déjà en place) ; PostgreSQL envisageable plus tard, sans blocage grâce à EF Core. |
| C4 | Ports : Auth 5011 (roadmap) vs 5001 (gateway, Doctor Mgmt) ; Analytics 5011 ; Payments 5005 vs 5004 ; Prescriptions 5004 vs 5007 | Roadmap tech, UC Consultation, ocelot.json | Sans objet avec le monolithe (un seul hôte). |
| C5 | Statut « Medical Records TERMINÉ » : chiffrement AES-256, audit trail, export RGPD | Roadmap tech | **Faux** : non implémentés dans le code (voir DIAGNOSTIC). Statut réel : partiel. |
| C6 | Libellés du DME : « Signes vitaux », « Maladies chroniques », « Nom de la maladie » | UC MR vs retours du 06/06 | Retenir **« Paramètres vitaux », « Antécédents médicaux », « Commentaires »** ; supprimer le statut Actif/Inactif. |
| C7 | Dose des vaccins : définie par patient (UC) ou par vaccin (retours) | UC-BACKEND-09 vs retours du 06/06 | **Par vaccin**, avec âge min/max et genre ciblé ; vaccins éligibles calculés à l'ouverture du DME. |
| C8 | Inscription : un compte par médecin vs rattachement multi-structures | CDC (profils) vs Observations | **Un compte médecin, N lieux d'exercice ; au moins un lieu requis pour validation.** |
| C9 | Modèle de revenus : abonnement professionnel (CDC) vs commission | CDC §7 vs Observations | **Commission sur toute téléconsultation** ; abonnement pour les centres de santé ; remboursement si la consultation n'a pas eu lieu. |
| C10 | Traduction : dioula/bété (CDC) vs FR/EN | CDC | FR seul au MVP ; i18n prévue dans le code dès le départ. |

---

## 3. Vision, cibles, profils

- **Vision** : plateforme e-santé (téléconsultation, RDV, carnet de santé, ordonnances, paiement mobile) pour la Côte d'Ivoire (phase 1), puis l'Afrique de l'Ouest.
- **Profils (menus selon le rôle)** : Patient (et ses **proches** : enfants, parents), Médecin, Professionnel paramédical (infirmier, sage-femme, kiné, psychologue), Pharmacien, Laboratoire, Établissement (clinique, cabinet, centre de santé, entreprise), Administrateur plateforme.
- **Contexte** : réseau 2G/3G instable, usage majoritaire sur smartphone Android d'entrée de gamme, paiement par Mobile Money.

## 4. Règles métier (sources : Observations du 26/04/2026, CDC)

1. Un médecin doit être rattaché à **au moins une structure** (ou déclaré « exercice libre ») pour être approuvé ; on affiche la structure sur sa fiche.
2. Un médecin a **un seul compte**, lié à N structures ; un planning par lieu d'exercice.
3. Le patient choisit le médecin, puis un créneau en **téléconsultation** ou en **présentiel**.
4. Médecin sans structure : téléconsultation possible, tarif propre au médecin.
5. Tarification : prix homologué ; **commission** sur chaque téléconsultation (individuel ou centre) ; **abonnement** pour les centres de santé (Standard 25 000 FCFA/mois, Pro 80 000 FCFA/mois, options dès 5 000 FCFA).
6. La commission est prélevée à la prise de RDV ; **remboursement** si la consultation n'a pas eu lieu. **MANQ** : comment patient et médecin confirment-ils qu'une visio a bien eu lieu ?
7. Validation professionnelle : numéro ONMCI + diplômes ; vérification manuelle par l'administrateur au MVP.
8. Vaccins : nombre de doses défini par vaccin ; éligibilité selon l'âge et le genre ; rappels affichés sur le tableau de bord du DME.

## 5. Exigences non fonctionnelles de référence (révisées pour 1 développeur et 1 VPS)

| Domaine | Exigence retenue | Statut |
|---|---|---|
| Mobile | Mobile-first, PWA installable, cibles tactiles ≥ 44 px, barre d'onglets en bas | SPEC |
| Hors ligne | Consultation hors ligne : DME du patient, agenda du jour, RDV à venir, ordonnances. Saisie hors ligne (notes, constantes) placée en file d'attente puis synchronisée, avec clé d'idempotence | CONTRA (C1) → SPEC ici |
| Bas débit | Pagination 10 à 20, GZIP/Brotli, squelettes de chargement, images compressées, dégradation vidéo → audio → téléphone | UC (Consultation) |
| Cache | Cache de sortie et cache mémoire côté serveur ; Redis seulement si plusieurs instances ; Cache API et IndexedDB côté client | SPEC |
| Sécurité santé | TLS ; chiffrement au repos des champs sensibles (diagnostic, notes, documents) ; **contrôle d'accès par propriétaire et par relation de soin** ; journal d'audit des accès au DME ; secrets hors du code ; sauvegarde chiffrée quotidienne | SPEC (non implémenté) |
| Conformité | Loi ivoirienne 2013-450 / ARTCI (déclaration du traitement de données de santé), consentement, export et suppression des données (RGPD pour la diaspora) | SPEC |
| Disponibilité | Visée réaliste MVP : 99,5 % (un VPS + sauvegardes) ; 99,9 % et 100 k utilisateurs simultanés reportés | CONTRA → révisé |
| IA | Phase ultérieure, derrière une interface dédiée ; aucune donnée identifiante envoyée à un LLM externe sans consentement | MANQ |
| Interopérabilité | HL7 FHIR et intégration PASS MOUSSO/SANTE CIV : phase 3 | SPEC |

---

## 6. Fonctionnalités par module

Priorité : **P1** = MVP (Abidjan), **P2** = extension nationale, **P3** = plus tard.

### M1 : Authentification et identité (P1)
| Fonctionnalité | Statut |
|---|---|
| Inscription Patient / Médecin (Établissement, Pharmacien, Labo : MANQ) | SPEC |
| Connexion e-mail ou **téléphone** + mot de passe (le téléphone est prioritaire en CI) | SPEC (téléphone : MANQ) |
| JWT + refresh token avec rotation | SPEC |
| 2FA TOTP ; OTP par SMS (Orange/MTN) | SPEC |
| Vérification de l'e-mail et du téléphone | SPEC |
| Mot de passe oublié / réinitialisation | SPEC |
| RBAC : rôles + permissions par module | SPEC |
| Vérification d'identité (CNI, passeport, CMU) | SPEC |
| SSO, biométrie | SPEC (P3) |

### M2 : Utilisateurs, professionnels et établissements (P1)
| Fonctionnalité | Statut |
|---|---|
| Profil complet + photo de profil | SPEC (photo : demandée le 06/06) |
| Dépôt des documents justificatifs | SPEC |
| Workflow de validation médecin (ONMCI, diplômes) par l'administrateur | SPEC |
| **Établissements et lieux d'exercice** (médecin ↔ N structures) | MANQ (règle métier connue, ni modèle ni UC) |
| **Proches rattachés au compte patient** (enfants, parents) | MANQ (vu chez Doctolib/Maiia, absent des specs) |
| Annuaire et fiche publique médecin, spécialités, avis | SPEC (P2) |
| Administration des utilisateurs (liste, statut, blocage) | SPEC |

### M3 : Carnet de santé / DME (P1) : UC-BACKEND-00 à 16, UC-FRONTEND-00 à 13
| Fonctionnalité | Statut |
|---|---|
| Dossier médical : création, lecture, mise à jour, suppression logique | UC |
| Antécédents médicaux (catégories CIM-10 + affections) | UC + retours 06/06 |
| Allergies | UC |
| Paramètres vitaux + historique + graphiques (TA, T°, SpO2, glycémie, IMC, FR, diurèse) | UC |
| Vaccinations + rappels en retard + **vaccins éligibles par âge et genre** | UC + retours 06/06 |
| Antécédents chirurgicaux + comptes rendus | UC |
| Documents médicaux : envoi, liste, téléchargement, suppression | UC |
| Antécédents gynéco-obstétricaux, antécédents familiaux, mode de vie (tabac, alcool, vapotage), traitements réguliers | SPEC (CDC) → **MANQ (pas d'UC)** |
| Contacts d'urgence, informations administratives | SPEC → MANQ (UC) |
| Timeline chronologique | UC |
| Recherche patient (médecin/admin) | UC |
| Export JSON / PDF / XML (RGPD) | UC |
| Journal d'audit des accès | UC |
| Chiffrement AES-256 des champs sensibles | SPEC (aucun UC précis) |
| **Règles d'accès : quel médecin voit quel DME (relation de soin, consentement, urgence)** | **MANQ (critique)** |

### M4 : Consultations et RDV (P1) : UC-API-CON-00 à 16, UC-FRONT-CON-00 à 13
| Fonctionnalité | Statut |
|---|---|
| Recherche de médecin (spécialité, ville, type, tarif) | UC |
| Disponibilités, créneaux, récurrence | UC |
| Réservation atomique + idempotence | UC |
| Cycle de vie : En attente → Confirmé → En cours → Terminé / Annulé / Absent / Reprogrammé | UC |
| Notes de consultation (diagnostic chiffré), lien DME | UC |
| Agenda médecin jour/semaine, statistiques | UC |
| Salle d'attente virtuelle | UC |
| Temps réel (SignalR) et mode économique | UC |
| Planning **par lieu d'exercice** | MANQ (lié à M2) |
| Confirmation bilatérale qu'une consultation a eu lieu (déclenche la commission) | MANQ |

### M5 : Téléconsultation vidéo/audio (P1)
| Fonctionnalité | Statut |
|---|---|
| Vidéo WebRTC + signalisation SignalR, serveur TURN/STUN | SPEC |
| Bascule audio en bas débit, chat, partage de fichiers | SPEC |
| Enregistrement avec consentement, partage d'écran, consultation de groupe | SPEC (P3) |
| Choix technique : WebRTC maison ou service tiers (Jitsi auto-hébergé, LiveKit) | MANQ (décision) |

### M6 : Ordonnances numériques (P1)
| Fonctionnalité | Statut |
|---|---|
| Prescription par le médecin, PDF côté serveur | SPEC |
| QR code signé + vérification en pharmacie | SPEC |
| Base médicamenteuse (Vidal coûteux → base ivoirienne à constituer) | CONTRA/MANQ |
| Interactions, posologie selon âge/poids | SPEC (P2) |

### M7 : Paiement (P1)
| Fonctionnalité | Statut |
|---|---|
| Mobile Money (Orange, MTN, Moov, Wave) via un agrégateur (CinetPay, PayDunya…) | SPEC (agrégateur : MANQ) |
| Commission plateforme, remboursement, facturation | SPEC + règles §4 |
| Abonnement des centres de santé | SPEC |
| Wallet, cartes (Stripe), multi-devises, paiement fractionné | SPEC (P2/P3) |

### M8 : Notifications (P1)
| Fonctionnalité | Statut |
|---|---|
| Rappels de RDV et de vaccins : push web, SMS, e-mail, WhatsApp | SPEC |
| Préférences par utilisateur | SPEC |
| Cloche de notifications en temps réel | SPEC |

### M9 : Administration et back-office (P1 minimal)
| Fonctionnalité | Statut |
|---|---|
| Validation des médecins, gestion des utilisateurs et des structures | SPEC |
| Référentiels : catégories de maladies, vaccins, spécialités | SPEC (en partie existant) |
| Journal d'audit, supervision des transactions | SPEC |
| Statistiques et KPI | SPEC (P2) |

### Modules P2/P3 (spécifiés au niveau liste uniquement, sans UC)
Pharmacie connectée (garde, stock, réservation, fiche médicament comme Maiia), Messagerie patient-médecin, Prestations à domicile (géolocalisation, matching), Laboratoire (prescription, résultats, valeurs critiques), Planning avancé (liste d'attente, no-show), Analytics, Télésurveillance/IoT, Formation et prévention, Support, Avis, Contenus, Multilingue, Interopérabilité externe (PASS MOUSSO, SANTE CIV, FHIR), **IA** (assistant patient, aide au médecin, suggestions de créneaux, pré-diagnostic). Statut : **SPEC sans UC**.

---

## 7. Manques à spécifier avant de coder (par ordre d'urgence)

1. **Matrice d'accès aux données de santé** : qui lit/écrit quel DME (patient, proche, médecin traitant, médecin consulté, urgence, admin), durée de l'accès, consentement.
2. **Établissements et lieux d'exercice** : modèle de données, planning par lieu, abonnement par structure.
3. **Comptes proches** (mineurs, personnes âgées) : consentement, bascule de profil.
4. **Preuve de consultation réalisée** et règles de remboursement/commission.
5. **Périmètre hors ligne** exact (données en lecture locale, saisies autorisées, résolution des conflits).
6. **Agrégateur de paiement** et opérateur SMS retenus.
7. Rubriques du DME sans UC : antécédents familiaux, gynéco-obstétricaux, mode de vie, traitements, contacts d'urgence.
8. Base médicamenteuse ivoirienne (source, mise à jour).
9. Choix vidéo (WebRTC maison ou Jitsi/LiveKit auto-hébergé) et budget du serveur TURN.
10. Cadre IA : cas d'usage, consentement, fournisseur, hébergement des données.

## 8. Périmètre MVP de référence (ordre de réalisation)

1. Socle : authentification par téléphone/e-mail, profils, rôles, menus par profil, PWA (shell hors ligne).
2. M2 Établissements + validation médecin.
3. M3 DME : mise en conformité sécurité + retours du 06/06 + rubriques manquantes.
4. M4 Consultations/RDV (présentiel et téléconsultation).
5. M7 Paiement Mobile Money + commission.
6. M5 Visio (bascule audio).
7. M6 Ordonnance QR.
8. M8 Notifications (SMS, push).
9. M9 Back-office minimal.
→ Ensuite : Pharmacie, Messagerie, IA (assistant), Domicile, Laboratoire.
