# Prompt Claude Code : Sprint 4 (dossier médical : rubriques, édition, timeline) à coller tel quel

```
SPRINT 4 : module MedicalRecords : rubriques complètes, édition, vaccins éligibles, documents, timeline

Contexte : sprint 3 validé. Relis le README du dépôt, CLAUDE.md, docs/EXPLOITATION.md et D:\ENTREPRISE FAMILIALE\PROJETS\PROJET DOCTOZEN\_DIAGNOSTIC\ (00-ETAT-DU-PROJET.md à jour, 01-SPECS_REFERENCE.md §6 M3 et décisions C6 et C7 §2). Mêmes règles : performance, réutilisabilité, clean architecture, petits commits, aucun contenu clinique en cache serveur, politiques nommées uniquement, pas de nouveaux documents d'explication, tests unitaires + intégration pour chaque flux. Le code du module est repris de l'ancien projet : corrige au passage tout ce qui n'est pas conforme à ces règles. Tout changement d'exploitation met à jour docs/EXPLOITATION.md (règle de CLAUDE.md).

0. POLISSAGE UI ISSU DU TEST VISUEL SUR MOBILE (en tout premier, petits commits)
Le rendu général est validé. Corrige :
a. Libellés : plus aucune valeur technique anglaise affichée. Dictionnaire de libellés français centralisé et réutilisable pour toutes les énumérations (groupes sanguins « O+ », « A- »…, sévérités « Sévère / Modérée / Légère », types de paramètres vitaux « Tension artérielle », « Température », « SpO2 », « Glycémie », « Poids »…, statuts, types de rubriques). Exemples vus : « OPositive », « Severe », « BloodPressure ».
b. Mon dossier, en-tête : « 175 cm · 78 kg » (espace manquant avant le point médian) ; valeurs absentes affichées « Non renseigné » plutôt que masquées.
c. Antécédents : le titre affiché est « Antécédent » (générique) ; afficher le nom de l'affection (CIM-10) ou le libellé saisi, avec la date, le médecin ou la mention « déclaré par le patient ». Corrige aussi le seed si l'affection n'est pas renseignée.
d. Paramètres vitaux : la tension s'affiche « 135/85 mmHg » (systolique/diastolique), libellé français, date relative (« il y a 7 jours »). Vérifie que la diastolique est bien stockée et affichée.
e. Cartes : supprime l'espace vide en bas des cartes de rubrique ; les pastilles de filtre qui défilent horizontalement (rubriques du dossier, filtres de l'annuaire) montrent un fondu à droite pour signaler qu'on peut faire défiler.
f. Mes proches : texte de la ligne en deux lignes courtes (« Parent · 74 ans » puis « Né(e) le 02/06/1952 »), boutons « Dossier » et « Modifier » alignés sans écraser le texte (le second en action secondaire ou menu « ⋯ » sur 360 px) ; marge entre la carte des proches et le bouton « Ajouter un proche » ; marge haute de la page comme les autres pages.
g. Tous les écrans : espace bas suffisant pour que le dernier élément ne soit jamais masqué par la barre d'onglets (padding-bottom = hauteur de la barre + zone sûre iOS).
h. En-tête : le sélecteur « Moi / Proche » affiche l'initiale ou l'avatar du profil actif et son nom (ex. « R Rose »), sans doubler avec la pastille de compte à droite ; pastille de compte = menu compte/déconnexion. Le nom du proche actif doit rester visible quand on consulte son dossier.
i. Annuaire : sous le nom, afficher la ville et le prix de consultation s'il existe ; avatars avec photo si disponible, sinon initiales (déjà fait) ; état vide soigné (« Aucun médecin ne correspond ») avec bouton « Effacer les filtres ».
j. Test d'intégration intermittent (envoi de la photo de profil) : trouve la cause réelle (concurrence, état partagé, fichier verrouillé) et corrige-la ; pas de contournement par retry. La suite complète doit passer 10 fois de suite.

A. DROITS D'ÉCRITURE (avec tests)
1. Le médecin validé ayant une relation de soin avec le patient (ou le proche) écrit les rubriques cliniques : antécédents médicaux, allergies, paramètres vitaux, vaccinations, chirurgies, traitements, documents.
2. Le patient ou le titulaire (pour un proche) renseigne seulement les rubriques déclaratives : informations administratives, contacts d'urgence, mode de vie (tabac, alcool, vapotage, activité), antécédents familiaux, antécédents gynéco-obstétricaux. Chaque entrée porte sa source (« déclaré par le patient » ou le médecin auteur) et sa date, affichées dans l'interface.
3. Toute écriture est auditée (acteur, rubrique, identifiant court du patient, action) sans copier le contenu clinique dans le journal. Suppression logique uniquement, jamais physique. Un médecin ne modifie pas une entrée d'un autre médecin sans la tracer (historique des versions simple : auteur, date, valeur précédente chiffrée).
4. Tests : un médecin sans relation de soin ne peut rien écrire ; un patient ne peut pas écrire une rubrique clinique ; un titulaire ne peut pas écrire dans le dossier du proche d'un autre titulaire ; l'admin n'a aucun accès.

B. RUBRIQUES ET LIBELLÉS (retours client du 06/06, voir 01-SPECS_REFERENCE.md C6 et C7)
5. Libellés exacts : « Paramètres vitaux », « Antécédents médicaux », « Commentaires » ; supprimer la notion Actif/Inactif des antécédents.
6. Antécédents médicaux avec catégories et affections CIM-10 (référentiel déjà seedé : 32 catégories, 40 affections), recherche sans accents.
7. Paramètres vitaux : tension, température, SpO2, glycémie, poids/taille/IMC (calculé), fréquence respiratoire, diurèse ; historique paginé ; valeurs hors plage signalées de façon sobre (couleur + texte, pas seulement couleur) ; graphique léger par paramètre (Chart.js déjà utilisé, chargé uniquement sur l'écran du graphique).
8. Vaccinations : dose définie par vaccin (pas par patient), âge minimum et maximum et genre ciblé ; à l'ouverture du dossier, calcule les vaccins éligibles selon l'âge et le genre et les rappels en retard ; affiche-les sur le tableau de bord du dossier et dans « Mon dossier ».
9. Chirurgies avec comptes rendus ; traitements réguliers (médicament libre pour l'instant, la base médicamenteuse viendra plus tard) ; allergies avec sévérité.
10. Documents : envoi, liste, téléchargement et suppression (suppression logique), via IDocumentStorage chiffré ; limites de taille et types autorisés (PDF, JPEG, PNG), contrôle du contenu réel du fichier (pas seulement l'extension), nom de fichier assaini, aperçu image compressé pour mobile.

C. INTERFACE (mobile-first, épurée, inspirée de la capture IMAGE 2 Doctolib « Profil santé »)
11. Remplace tout reste de tableau de bord monolithique : l'écran « Mon dossier » est une liste de rubriques avec icône, compteur et dernière mise à jour ; chaque rubrique ouvre un écran court (liste paginée + bouton ajouter), chargé séparément pour rester léger en 3G.
12. Formulaires courts, un champ principal par écran quand c'est possible, validation côté client et serveur, messages en français clair, cibles tactiles >= 44 px, retour (←) en haut à gauche, titre centré. Bascule « Moi / Proche » respectée partout, avec le nom du proche toujours visible dans l'en-tête.
13. Vue médecin : depuis la fiche d'un patient autorisé, mêmes rubriques avec boutons d'édition ; indique clairement qu'un accès est journalisé.
14. Réponses cliniques avec Cache-Control: no-store ; compression Brotli déjà en place ; pagination par clés (keyset) sur les listes longues ; index PostgreSQL adaptés aux requêtes de liste (patient + date) ; vérifie les plans de requête sur 100 000 lignes de test pour les rubriques à gros volume (paramètres vitaux) et note le résultat dans le résumé.

D. TIMELINE
15. Écran chronologique fusionnant toutes les rubriques (vaccins, chirurgies, antécédents, vitaux, documents, allergies) triées par date, filtrables par type, paginées par clés, léger en 3G. Aucune donnée clinique en cache serveur.

E. RESTES DU SPRINT 3
16. Page de validation des médecins par l'admin : affiche les lieux d'exercice déclarés. Notifications (SMS/e-mail via ISmsSender/IEmailSender déjà en place) quand un lieu est validé ou refusé et quand une reprise de dossier a lieu.

F. QUALITÉ
17. Tests d'architecture inchangés et verts ; 0 avertissement ; 0 paquet vulnérable ; gitleaks propre sur tout l'historique avant chaque push.
18. Mets à jour le README, docs/EXPLOITATION.md et smoke.http (nouvelles données de test : un dossier complet pour patient1 avec chaque rubrique remplie, un proche avec vaccins en retard).
19. Si une règle ci-dessus entre en conflit avec le code existant ou la spec, ne devine pas : applique l'option la plus prudente pour la sécurité des données de santé et signale-la dans le résumé.
20. Vérifie visuellement les pages principales dans un navigateur automatisé en largeur mobile (360 px) et desktop, et joins au résumé la liste de ce qui reste à contrôler sur un vrai téléphone.

Ne pousse rien sur GitHub sans que je te l'aie confirmé dans la conversation. À la fin : résumé de 15 lignes maximum et liste de ce qui reste à faire.
```
