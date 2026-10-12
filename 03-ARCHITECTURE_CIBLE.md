# DoctoZen : architecture cible (décisions au 09/10/2026)

## 1. Décisions verrouillées

| Sujet | Décision |
|---|---|
| Style | **Monolithe modulaire .NET 8** : un dépôt, une solution, un hôte, des modules étanches. Microservices écartés tant qu'un seul développeur. |
| Dépôt | **Nouveau dépôt unique, sans historique** des 8 anciens (ils contiennent des secrets). On reprend le code par déplacement. |
| Base de données | **PostgreSQL 16** (Npgsql + EF Core 8). Un schéma par module (`identity`, `directory`, `mr`, `scheduling`, ...), aucune clé étrangère entre schémas. |
| Cache | **Redis** derrière `ICacheService` (référentiels, limitation de débit, listes chaudes). |
| Front | **Razor MVC/Pages côté serveur + modules JS ES réutilisables**, mobile-first, **PWA** (service worker, IndexedDB, file de synchronisation). Blazor Server exclu. |
| Interface | Un seul shell : barre d'onglets en bas (mobile) / barre latérale (desktop), **registre de menus par profil**. Thème bleu ciel et blanc, épuré. |
| Auth | Cookie HttpOnly pour l'UI, JWT pour `/api/v1` (mobile futur). |
| IA | `IAssistantService` dès le socle ; pipeline NOVA porté en C# : règles d'abord, LLM en dernier recours, carte de validation avant toute action. |
| Hébergement | Nouveau VPS dédié (distinct de celui de NOVA) : Nginx -> Kestrel, systemd, Let's Encrypt, PostgreSQL + Redis. |

## 2. Pourquoi PostgreSQL

- **Coût** : licence gratuite. SQL Server Standard est payant et Express est plafonné (10 Go par base, peu de RAM), donc inadapté à des millions d'utilisateurs.
- **Charge** : 10 000 utilisateurs tiennent sur un seul VPS. Pour des millions, la voie de montée en charge est connue : PgBouncer (pool de connexions), index adaptés, partitionnement des grosses tables (audit, mesures vitales, notifications), réplicas en lecture, puis serveur géré si besoin.
- **Coût de migration** : faible. EF Core masque la différence ; on régénère les migrations par module pour Npgsql. Types à surveiller : `Guid`, `DateTimeOffset` (utiliser UTC), `jsonb` pour les champs semi-structurés.
- **Exploitation** : vous avez déjà un VPS qui fait tourner PostgreSQL ; même outillage (sauvegardes `pg_dump`, `pgBackRest` plus tard).
- **Point d'attention** : les noms de tables et colonnes en `snake_case` (convention Npgsql), le seed SQL existant (`script_MedicalRecord_Insert.sql`) est à réécrire en seed EF Core ou en SQL PostgreSQL.

## 3. Structure cible

```
DoctoZen/                       (1 dépôt, 1 .sln)
  src/
    DoctoZen.Web/               Hôte unique : Razor + API /api/v1
      Shell/                    layout, registre de menus par profil, service worker, manifeste
      wwwroot/js/modules/       modules JS ES réutilisables (api-client, offline-queue, ui-kit)
    Modules/
      Identity/                 ex-Authentication
      Directory/                profils, établissements, lieux d'exercice, proches, validation médecin
      MedicalRecord/            ex-MedicalRecords (couches conservées)
      Scheduling/               consultations et RDV
      Teleconsult/ Prescriptions/ Payments/ Notifications/ Admin/
      Assistant/                IA (interface dès le socle)
      (chaque module : Domain | Application | Infrastructure | Contracts | Web)
    BuildingBlocks/             Result, pagination, audit, chiffrement, outbox, horloge, i18n, ICacheService
  tests/                        unitaires par module, tests d'architecture (NetArchTest), intégration (Testcontainers PostgreSQL)
  deploy/                       docker-compose (dev), nginx.conf, doctozen.service, deploy.ps1 (inspiré de NOVA)
```

Règles : un module n'appelle les autres que par leurs **Contracts** (interfaces et événements en mémoire) ; un test d'architecture interdit les références croisées. Chaque module expose son menu au registre du shell (entrées, rôles, icône).

## 4. Sécurité et conformité (non négociables avant toute donnée réelle)

1. Secrets hors dépôt (user-secrets en local, variables d'environnement sur le VPS) + contrôle gitleaks en CI.
2. Contrôle d'accès par propriétaire et par relation de soin sur chaque endpoint du dossier médical.
3. Chiffrement des champs sensibles (converter EF, clé hors base) et journal d'audit des lectures.
4. Refresh tokens hachés, limitation de débit .NET 8, HTTPS strict.
5. Conformité : loi ivoirienne 2013-450 (ARTCI), consentement, export et suppression des données.
6. IA : consentement explicite, aucune donnée identifiante vers un LLM externe, pas de pré-diagnostic au MVP.

## 5. Hors ligne (PWA)

- Lecture locale : DME du patient, agenda du jour, RDV à venir, ordonnances (IndexedDB + Cache API).
- Saisies hors ligne (notes, constantes) : file d'attente avec clé d'idempotence, synchronisation au retour du réseau (Background Sync). Résolution de conflit à spécifier.
- Service worker repris du modèle NOVA (cache versionné, network-first).

## 6. Plan de reprise (~16 semaines, 1 développeur)

| Sprint | Contenu |
|---|---|
| S0 (1-2 jours) | Révoquer jeton GitHub, mot de passe Gmail, clé JWT, mot de passe `sa`, mot de passe SFTP. Vérifier que les anciens dépôts sont privés. |
| S1 | Nouveau dépôt, squelette, BuildingBlocks, CI, docker-compose (PostgreSQL + Redis), seed cohérent, compte admin |
| S2 | Identity : cookie + JWT, inscription téléphone/e-mail, OTP, vérification, rôles et policies |
| S3 | Shell mobile-first + registre de menus + PWA ; Directory : profils, établissements, proches, validation médecin |
| S4-S5 | MedicalRecord : accès par relation de soin, chiffrement, audit, export, retours du 06/06, rubriques manquantes, lecture hors ligne |
| S6-S7 | Scheduling : créneaux, réservation idempotente, agenda, file de synchronisation |
| S8 | Payments (Mobile Money) + Notifications (push, SMS, rappels) |
| S9 | Téléconsultation (Jitsi/LiveKit ou WebRTC + coturn), bascule audio |
| S10 | Ordonnance QR, durcissement, déploiement VPS, pilote |
| Ensuite | Assistant IA, pharmacie, messagerie |

À conserver : entités et configurations EF du DME, services Application de MR, logique AuthService/JwtService, use cases Consultation, graphiques des paramètres vitaux, seed des référentiels (à porter PostgreSQL).
À abandonner : ApiGateway, Shared.Contracts/Infrastructure, NuGet privé, les 8 dépôts, Metronic, PatientDashboard monolithique, SFTP, scripts PowerShell 1-14.
