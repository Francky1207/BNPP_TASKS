# Prompt Claude Code : Sprint 2 (Identity et sécurité) à coller tel quel

```
SPRINT 2 : module Identity complet + corrections de sécurité prioritaires

Contexte : le socle sprint 0/1 est validé (C:\Users\aurel\source\repos\DoctoZen). Relis le README du dépôt et D:\ENTREPRISE FAMILIALE\PROJETS\PROJET DOCTOZEN\_DIAGNOSTIC\ (00-ETAT-DU-PROJET.md à jour, 01-SPECS_REFERENCE.md §6 M1/M2). Mêmes règles : performance, réutilisabilité, clean architecture, petits commits, pas de nouveaux documents d'explication, explications courtes pour tout ce qui touche Docker ou PostgreSQL.

A. SÉCURITÉ D'ABORD (premiers commits)
1. Cache Redis : plus aucun contenu clinique dans le cache (dossier détaillé, notes, allergies, etc.). Ne cacher que les référentiels (CIM-10, vaccins, spécialités) et des données non cliniques. Ajoute un test qui échoue si une clé de cache clinique est écrite.
2. Sessions : un compte suspendu, supprimé ou dont le mot de passe/rôle a changé doit perdre sa session en moins de 2 minutes (security stamp vérifié à chaque requête avec cache court, ou à intervalle de 1-2 min). Déconnexion de tous les appareils à la réinitialisation du mot de passe. Test d'intégration.
3. Les comptes de test et le seed de dev (mot de passe DoctoZen-Dev-2026!) ne s'exécutent JAMAIS hors environnement Development ; échec au démarrage si on essaie en Production. Test.
4. Lance gitleaks sur tout l'historique du dépôt et confirme qu'il est propre avant tout push.

B. IDENTITY (fonctionnalités)
5. Inscription mobile-first en 2 étapes (patient, puis professionnel de santé), téléphone en premier. Numéros ivoiriens : normalisation E.164 (+225, numéros à 10 chiffres) avec la bibliothèque libphonenumber (paquet NuGet PhoneNumbers), unicité du téléphone et de l'e-mail.
6. Connexion par téléphone OU e-mail + mot de passe. Messages d'erreur identiques pour compte inconnu et mot de passe faux (pas d'énumération de comptes).
7. Vérification du téléphone par code OTP (6 chiffres, expiration 5 min, 5 essais max, hachés en base, limitation de débit par numéro et par IP). Interface ISmsSender avec une implémentation de développement qui écrit le code dans les logs ; le fournisseur SMS réel sera choisi plus tard (ne pas en choisir un). Vérification de l'e-mail par lien signé à durée limitée ; interface IEmailSender avec SMTP configurable par secrets, et Mailpit dans docker-compose pour le dev.
8. Mot de passe oublié et réinitialisation (pages Razor, par téléphone OTP ou e-mail), politique de mot de passe cohérente, verrouillage progressif persistant en base (plus en mémoire).
9. 2FA TOTP : pages d'activation avec QR code et codes de secours, déjà chiffré côté secret.
10. Rôles et policies : Patient, Doctor, Admin, avec policies nommées utilisées partout (plus de [Authorize(Roles=...)] en chaîne de caractères). Un médecin n'a accès à rien de clinique tant que l'admin ne l'a pas validé.
11. Validation des médecins par l'admin (version minimale) : liste des demandes (numéro ONMCI, diplômes déposés), approuver/refuser avec motif, notification au médecin, journal d'audit.
12. Page profil patient et médecin (photo de profil comprise, stockée via IDocumentStorage, redimensionnée et compressée).
13. Le menu par profil affiche les nouvelles entrées selon le rôle.

C. QUALITÉ
14. Tests xUnit + tests d'intégration Testcontainers pour chaque flux (inscription, OTP, connexion, reset, verrouillage, suspension). Les tests d'intégration sont ignorés si Docker est absent, mais doivent passer quand il est installé : indique-moi comment installer et lancer Docker Desktop (Windows, WSL2) en 6 lignes maximum.
15. Tests d'architecture inchangés et verts. 0 paquet vulnérable. Corrige les 22 avertissements de nullabilité du code DME repris.
16. Mets à jour le README d'intégration (flux d'inscription, comptes de test, variables d'environnement requises). Ne modifie pas 00-ETAT-DU-PROJET.md.

Ne pousse rien sur GitHub tant que je ne l'ai pas confirmé. À la fin : résumé de 15 lignes maximum et liste de ce qui reste à faire.
```
