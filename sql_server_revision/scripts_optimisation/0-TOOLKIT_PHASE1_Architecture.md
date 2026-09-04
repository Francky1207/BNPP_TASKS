# SQL SERVER + ETL + WINDOWS — INVESTIGATION TOOLKIT
## PHASE 1 — Architecture complète, dictionnaire et priorités

**Version** : 1.0 — Phase 1 initiale
**Auteur** : Franck KOUAME — SEEDKA HOLDING
**Objectif** : Boîte à outils d'investigation professionnelle, documentée, sécurisée, utilisable en production

---

## SECTION A — ARCHITECTURE DES DOSSIERS

```
INVESTIGATION_TOOLKIT\
│
├── 00_MASTER\
│   ├── TOOLKIT_README.md                 ← guide d'entrée, comment utiliser la boîte à outils
│   ├── TOOLKIT_CONVENTIONS.md            ← règles de nommage et standards
│   ├── TOOLKIT_PERMISSIONS.md            ← droits nécessaires par script
│   └── TOOLKIT_PLAYBOOKS.md              ← procédures d'investigation complètes (Phase 3)
│
├── 01_DIAGNOSTIC_INITIAL\               ← PREMIÈRE CHOSE À EXÉCUTER face à un problème
│   ├── SQL\
│   └── PS\
│
├── 02_SESSIONS_ET_REQUETES\             ← Qui fait quoi, qui bloque qui, quelle requête tourne
│   ├── SQL\
│   └── PS\
│
├── 03_PERFORMANCES_REQUETES\            ← Lenteurs, plans d'exécution, consommation CPU/IO
│   ├── SQL\
│   └── PS\
│
├── 04_INDEX_ET_STATISTIQUES\            ← Index manquants, inutilisés, fragmentés, stats obsolètes
│   ├── SQL\
│   └── PS\
│
├── 05_BLOCAGES_ET_VERROUS\              ← Blocking, deadlocks, transactions longues
│   ├── SQL\
│   └── PS\
│
├── 06_MEMOIRE_CPU_IO\                   ← Pression mémoire, saturation CPU, I/O disque, tempdb
│   ├── SQL\
│   └── PS\
│
├── 07_FICHIERS_ET_STOCKAGE\             ← MDF/NDF/LDF, taille, croissance, espace disque
│   ├── SQL\
│   └── PS\
│
├── 08_OBJETS_BASE_DE_DONNEES\           ← Tables, vues, procs, fonctions, triggers, dépendances
│   ├── SQL\
│   └── PS\
│
├── 09_JOBS_ET_AGENT\                    ← SQL Server Agent, historique, échecs, durées
│   ├── SQL\
│   └── PS\
│
├── 10_ETL_CHAINE_TRAITEMENT\            ← Investigation spécifique CRE→TFT→ODS→IC
│   ├── SQL\
│   └── PS\
│
├── 11_QUALITE_DONNEES\                  ← Doublons, NULL, volumes, écarts entre étapes
│   ├── SQL\
│   └── PS\
│
├── 12_WINDOWS_SERVEUR\                  ← CPU, RAM, disque, réseau, processus Windows
│   └── PS\
│
├── 13_FICHIERS_LOGS_CRE\               ← Lecture, parsing et analyse des logs DATA STUDIO
│   ├── SQL\
│   └── PS\
│
├── 14_QUERY_STORE\                      ← Query Store (SQL Server 2016+)
│   └── SQL\
│
├── 15_COMPARAISONS_ET_MESURES\          ← Avant/après optimisation, benchmarks
│   ├── SQL\
│   └── PS\
│
└── 99_TEMPLATES\                        ← Modèles réutilisables
    ├── TEMPLATE_SQL_Script.sql
    ├── TEMPLATE_PS_Script.ps1
    └── TEMPLATE_Analyse_Rapport.md
```

---

## SECTION B — CONVENTION DE NOMMAGE

### Format général

```
[TECH]_[CATEGORIE]_[NUMERO]_[ACTION]_[OBJET].[extension]
```

### Légende

| Champ | Valeurs | Exemples |
|---|---|---|
| TECH | SQL, PS, CMD | SQL, PS |
| CATEGORIE | 2 lettres du dossier parent | DI (Diagnostic Initial), SR (Sessions/Requêtes)... |
| NUMERO | 01 à 99 | 01, 02, 15 |
| ACTION | verbe court | List, Get, Find, Analyze, Check, Compare, Monitor |
| OBJET | sujet court | SlowQueries, Indexes, Blocking, TableSize... |

### Table de correspondance catégories

| Dossier | Code | Exemples de noms |
|---|---|---|
| 01_DIAGNOSTIC_INITIAL | DI | SQL_DI_01_Get_Server_Health.sql |
| 02_SESSIONS_ET_REQUETES | SR | SQL_SR_01_List_Active_Sessions.sql |
| 03_PERFORMANCES_REQUETES | PQ | SQL_PQ_01_Find_SlowQueries_Cache.sql |
| 04_INDEX_ET_STATISTIQUES | IX | SQL_IX_01_Find_Missing_Indexes.sql |
| 05_BLOCAGES_ET_VERROUS | BL | SQL_BL_01_Analyze_Current_Blocking.sql |
| 06_MEMOIRE_CPU_IO | MC | SQL_MC_01_Check_Memory_Pressure.sql |
| 07_FICHIERS_ET_STOCKAGE | FS | SQL_FS_01_Analyze_Database_Files.sql |
| 08_OBJETS_BASE_DE_DONNEES | OB | SQL_OB_01_Inspect_Table_Structure.sql |
| 09_JOBS_ET_AGENT | JA | SQL_JA_01_List_Failed_Jobs.sql |
| 10_ETL_CHAINE_TRAITEMENT | ET | SQL_ET_01_Compare_TFT_vs_ODS.sql |
| 11_QUALITE_DONNEES | QD | SQL_QD_01_Find_Duplicates.sql |
| 12_WINDOWS_SERVEUR | WS | PS_WS_01_Get_Server_Resources.ps1 |
| 13_FICHIERS_LOGS_CRE | LC | PS_LC_01_Parse_DataStudio_Logs.ps1 |
| 14_QUERY_STORE | QS | SQL_QS_01_Find_Regressed_Queries.sql |
| 15_COMPARAISONS_ET_MESURES | CM | SQL_CM_01_Benchmark_Before_After.sql |

### Marqueurs de sécurité dans le nom

Chaque script inclut dans son nom un suffixe de risque :

```
_RO  → READ ONLY  — peut être exécuté sans risque en production
_LR  → LOW RISK   — lecture + traitements légers (stats, DMV lourdes)
_MOD → MODIFICATION — modifie des données ou des objets (⚠️ validation requise)
```

### Exemples complets

```
SQL_DI_01_Get_Server_Health_RO.sql
SQL_SR_03_Find_Blocking_Sessions_RO.sql
SQL_IX_05_Rebuild_Fragmented_Indexes_MOD.sql
PS_WS_01_Get_CPU_RAM_Disk_Usage_RO.ps1
SQL_ET_02_Compare_RowCounts_TFT_ODS_RO.sql
```

---

## SECTION C — DICTIONNAIRE COMPLET DES SCRIPTS

*(Classés P0 à P3 — Production ready : P0 et P1 en priorité absolue)*

---

### 01 — DIAGNOSTIC INITIAL

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_DI_01_Get_Server_Health_RO.sql | Vue d'ensemble rapide du serveur : sessions, CPU, mémoire, waits | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_DI_02_Get_WaitStats_RO.sql | Top 15 des types d'attente — identifier le goulot d'étranglement principal | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_DI_03_List_Running_Queries_RO.sql | Toutes les requêtes en cours avec durée, CPU, état | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_DI_04_Find_Long_Running_Queries_RO.sql | Requêtes en cours depuis plus de X minutes | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_DI_05_Check_Blocking_Now_RO.sql | Y a-t-il du blocking actif en ce moment ? | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_DI_06_Get_Database_Status_RO.sql | État de toutes les bases (online, taille, recovery model) | SQL | RO | VIEW DATABASE STATE | **P0** |
| PS_DI_01_Get_Server_Resources_Snapshot_RO.ps1 | CPU, RAM, I/O disque, espace libre — snapshot Windows instantané | PS | RO | Lecteur local | **P0** |

---

### 02 — SESSIONS ET REQUÊTES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_SR_01_List_Active_Sessions_RO.sql | Toutes les sessions actives avec login, DB, état, durée | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_SR_02_Get_Session_Details_RO.sql | Détail complet d'une session spécifique (@SessionId) | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_SR_03_Find_Blocking_Chain_RO.sql | Qui bloque qui — chaîne complète de blocage | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_SR_04_Get_Query_Text_From_Session_RO.sql | Récupérer le texte SQL d'une session en cours | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_SR_05_Get_Active_Transactions_RO.sql | Transactions ouvertes, leur durée, leur log utilisé | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_SR_06_Find_Sessions_By_Database_RO.sql | Toutes les sessions connectées à une base précise | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_SR_07_Kill_Session_MOD.sql | Tuer une session (avec confirmation obligatoire) | SQL | **MOD** | ALTER ANY CONNECTION | P2 |
| SQL_SR_08_List_Historical_Queries_Cache_RO.sql | Requêtes historiques dans le plan cache | SQL | RO | VIEW SERVER STATE | **P1** |

---

### 03 — PERFORMANCES REQUÊTES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql | Top N requêtes par CPU total depuis redémarrage | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_PQ_02_Find_Top_Slow_Queries_IO_RO.sql | Top N requêtes par lectures logiques | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_PQ_03_Find_Top_Slow_Queries_Duration_RO.sql | Top N requêtes par durée moyenne d'exécution | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_PQ_04_Analyze_Query_With_Stats_RO.sql | Exécuter une requête avec SET STATISTICS IO/TIME | SQL | LR | db_datareader | **P0** |
| SQL_PQ_05_Get_Execution_Plan_Cached_RO.sql | Récupérer le plan d'exécution depuis le cache | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_PQ_06_Find_NonSARGable_Patterns_RO.sql | Détecter les fonctions sur colonnes indexées dans les WHERE | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_PQ_07_Find_Implicit_Conversions_RO.sql | Détecter les conversions implicites de types dans les plans | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_PQ_08_Analyze_Parameter_Sniffing_RO.sql | Comparer plan estimé vs réel, détecter le sniffing | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_PQ_09_Compare_Plan_Before_After_RO.sql | Comparer deux exécutions d'une même requête | SQL | LR | db_datareader | **P1** |
| SQL_PQ_10_Find_Parallel_Queries_RO.sql | Requêtes utilisant le parallélisme excessivement | SQL | RO | VIEW SERVER STATE | **P2** |
| SQL_PQ_11_Analyze_Memory_Grants_RO.sql | Requêtes avec memory grant excessif ou insuffisant | SQL | RO | VIEW SERVER STATE | **P2** |
| SQL_PQ_12_Find_Sort_Operations_RO.sql | Opérations de tri coûteuses dans le cache | SQL | RO | VIEW SERVER STATE | **P2** |

---

### 04 — INDEX ET STATISTIQUES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_IX_01_Find_Missing_Indexes_RO.sql | Index manquants suggérés par SQL Server — par impact | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_IX_02_List_Table_Indexes_RO.sql | Tous les index d'une table (@TableName) avec colonnes | SQL | RO | VIEW DEFINITION | **P0** |
| SQL_IX_03_Find_Unused_Indexes_RO.sql | Index non utilisés depuis dernier redémarrage | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_IX_04_Check_Index_Fragmentation_RO.sql | Fragmentation de tous les index d'une table ou base | SQL | LR | db_datareader | **P0** |
| SQL_IX_05_Check_Statistics_Freshness_RO.sql | Date et qualité des statistiques par table | SQL | RO | VIEW DEFINITION | **P0** |
| SQL_IX_06_Find_Duplicate_Indexes_RO.sql | Index redondants (mêmes colonnes ou sous-ensembles) | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_IX_07_Analyze_Index_Usage_Stats_RO.sql | Utilisation détaillée de chaque index : seeks, scans, updates | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_IX_08_Update_Table_Statistics_MOD.sql | Mettre à jour les stats d'une table (@TableName) | SQL | MOD | ALTER TABLE | P2 |
| SQL_IX_09_Rebuild_Index_Online_MOD.sql | Reconstruire un index en mode ONLINE | SQL | MOD | ALTER INDEX | P2 |
| SQL_IX_10_Reorganize_Index_MOD.sql | REORGANIZE un index fragmenté | SQL | MOD | ALTER INDEX | P2 |
| SQL_IX_11_Find_Covering_Index_Candidates_RO.sql | Candidats à l'ajout de colonnes INCLUDE | SQL | RO | VIEW SERVER STATE | P3 |

---

### 05 — BLOCAGES ET VERROUS

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_BL_01_Analyze_Current_Blocking_RO.sql | Analyse complète du blocking actuel : qui, quoi, depuis quand | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_BL_02_Get_Lock_Details_RO.sql | Détail des verrous actifs (type, ressource, session) | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_BL_03_Find_Deadlock_In_SystemHealth_RO.sql | Extraire les deadlocks de la session system_health | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_BL_04_Monitor_Blocking_Over_Time_RO.sql | Capturer le blocking toutes les N secondes (boucle courte) | SQL | LR | VIEW SERVER STATE | **P1** |
| SQL_BL_05_Find_Long_Transactions_RO.sql | Transactions ouvertes depuis plus de X minutes | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_BL_06_Analyze_Lock_Waits_RO.sql | Types d'attentes liés aux verrous : LCK_M_* | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_BL_07_Get_Deadlock_Graph_Extended_RO.sql | Graphe XML des deadlocks via Extended Events | SQL | RO | VIEW SERVER STATE | P2 |

---

### 06 — MÉMOIRE / CPU / I/O

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_MC_01_Check_Memory_Pressure_RO.sql | Pression mémoire SQL Server : buffer pool, target, used | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_MC_02_Check_CPU_Usage_RO.sql | CPU SQL Server vs OS depuis ring buffer | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_MC_03_Analyze_IO_By_Database_RO.sql | I/O par base de données depuis démarrage | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_MC_04_Check_Tempdb_Usage_RO.sql | Utilisation tempdb : espace, sessions, qui consomme | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_MC_05_Find_Top_IO_Tables_RO.sql | Tables générant le plus d'I/O | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_MC_06_Analyze_Buffer_Pool_By_DB_RO.sql | Pages en mémoire (buffer pool) par base | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_MC_07_Check_Tempdb_Contention_RO.sql | Contention de tempdb (allocation) | SQL | RO | VIEW SERVER STATE | **P1** |
| PS_MC_01_Monitor_Resources_Continuous_RO.ps1 | Monitoring continu CPU/RAM/IO Windows (toutes les N sec) | PS | RO | Lecteur local | **P1** |

---

### 07 — FICHIERS ET STOCKAGE

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_FS_01_Analyze_Database_Files_RO.sql | Taille, espace utilisé, croissance auto des MDF/NDF/LDF | SQL | RO | db_owner ou VIEW DEFINITION | **P0** |
| SQL_FS_02_Check_Log_File_Usage_RO.sql | Utilisation du fichier journal : % utilisé, log_reuse_wait | SQL | RO | VIEW DATABASE STATE | **P0** |
| SQL_FS_03_Get_All_Databases_Sizes_RO.sql | Taille de toutes les bases sur l'instance | SQL | RO | VIEW SERVER STATE | **P0** |
| SQL_FS_04_Analyze_File_Growth_Events_RO.sql | Événements de croissance automatique des fichiers | SQL | RO | VIEW DATABASE STATE | **P1** |
| PS_FS_01_Check_Disk_Space_All_Drives_RO.ps1 | Espace libre sur tous les lecteurs du serveur | PS | RO | Lecteur local | **P0** |
| PS_FS_02_Find_Large_Files_In_Directory_RO.ps1 | Gros fichiers dans un répertoire (CRE, logs) | PS | RO | Lecture dossier réseau | **P1** |
| PS_FS_03_Monitor_Directory_Size_RO.ps1 | Taille et évolution d'un répertoire partagé | PS | RO | Lecture dossier réseau | **P1** |

---

### 08 — OBJETS BASE DE DONNÉES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_OB_01_Inspect_Table_Structure_RO.sql | Colonnes, types, longueur, nullable, défaut d'une table | SQL | RO | VIEW DEFINITION | **P0** |
| SQL_OB_02_Get_Table_RowCount_Size_RO.sql | Nombre de lignes et taille d'une table | SQL | RO | db_datareader | **P0** |
| SQL_OB_03_List_All_Tables_With_Sizes_RO.sql | Toutes les tables d'une base avec lignes et taille | SQL | RO | db_datareader | **P0** |
| SQL_OB_04_Get_Top_Biggest_Tables_RO.sql | Top 30 des plus grosses tables d'une base | SQL | RO | db_datareader | **P0** |
| SQL_OB_05_List_Stored_Procedures_RO.sql | Toutes les procédures stockées avec dates | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_06_Get_Proc_Code_RO.sql | Afficher le code d'une procédure (@ProcName) | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_07_Find_Object_Dependencies_RO.sql | Dépendances d'un objet (qui l'utilise, qu'est-ce qu'il utilise) | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_08_List_Views_RO.sql | Toutes les vues d'une base avec définition | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_09_List_Triggers_RO.sql | Triggers actifs par table | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_10_Search_Text_In_Objects_RO.sql | Chercher un texte dans tout le code SQL (@SearchText) | SQL | RO | VIEW DEFINITION | **P1** |
| SQL_OB_11_Compare_Table_Structure_RO.sql | Comparer la structure de deux tables | SQL | RO | VIEW DEFINITION | P2 |
| SQL_OB_12_List_Foreign_Keys_RO.sql | Clés étrangères d'une table avec table parent | SQL | RO | VIEW DEFINITION | P2 |

---

### 09 — JOBS ET AGENT

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_JA_01_List_Failed_Jobs_Last24h_RO.sql | Jobs en échec dans les dernières 24h | SQL | RO | SQLAgentReaderRole | **P0** |
| SQL_JA_02_Get_Job_History_RO.sql | Historique d'un job (@JobName) : durées, succès/échec | SQL | RO | SQLAgentReaderRole | **P0** |
| SQL_JA_03_List_Running_Jobs_RO.sql | Jobs en cours d'exécution en ce moment | SQL | RO | SQLAgentReaderRole | **P0** |
| SQL_JA_04_Analyze_Job_Durations_RO.sql | Durées moyennes, min, max par job (détecter les dérives) | SQL | RO | SQLAgentReaderRole | **P1** |
| SQL_JA_05_List_All_Jobs_Schedule_RO.sql | Tous les jobs avec planification | SQL | RO | SQLAgentReaderRole | **P1** |
| SQL_JA_06_Find_Jobs_Running_Too_Long_RO.sql | Jobs en cours dépassant leur durée habituelle | SQL | RO | SQLAgentReaderRole | **P1** |

---

### 10 — ETL / CHAÎNE DE TRAITEMENT (spécifique à ton environnement)

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_ET_01_Compare_RowCounts_All_Layers_RO.sql | Comparer les volumes CRE→TFT→ODS→IC pour une entité | SQL | RO | db_datareader | **P0** |
| SQL_ET_02_Find_RowCount_Discrepancies_RO.sql | Détecter les pertes ou doublons entre couches | SQL | RO | db_datareader | **P0** |
| SQL_ET_03_Analyze_TFT_vs_ODS_RO.sql | Comparer TFT et ODS : lignes attendues vs réelles | SQL | RO | db_datareader | **P0** |
| SQL_ET_04_Analyze_ODS_vs_IC_RO.sql | Comparer ODS et IC : lignes attendues vs réelles | SQL | RO | db_datareader | **P0** |
| SQL_ET_05_Find_Orphan_Records_RO.sql | Lignes ODS sans correspondance IC ou TFT (@TableA, @TableB) | SQL | RO | db_datareader | **P0** |
| SQL_ET_06_Analyze_Last_Load_Timing_RO.sql | Quand chaque table a été chargée (via colonnes de date) | SQL | RO | db_datareader | **P1** |
| SQL_ET_07_Check_TFT_Data_Quality_RO.sql | Qualité des données dans les tables TFT (NULL, types) | SQL | RO | db_datareader | **P1** |
| SQL_ET_08_Find_Delta_Between_Runs_RO.sql | Différence entre deux exécutions (@DateRun1, @DateRun2) | SQL | RO | db_datareader | **P1** |
| SQL_ET_09_Analyze_ETL_Perf_By_Volume_RO.sql | Corréler volume de données et durée de traitement | SQL | RO | db_datareader + VIEW SERVER STATE | **P1** |
| SQL_ET_10_Find_Treatment_Bottleneck_RO.sql | Identifier quelle étape ETL prend le plus de temps | SQL | RO | VIEW SERVER STATE | **P1** |
| PS_ET_01_Check_CRE_Files_Status_RO.ps1 | Existence, taille, date des fichiers CRE avant traitement | PS | RO | Lecture dossier réseau | **P0** |
| PS_ET_02_List_CRE_Files_Recent_RO.ps1 | Fichiers CRE modifiés récemment dans un répertoire | PS | RO | Lecture dossier réseau | **P0** |
| PS_ET_03_Check_Input_Files_Format_RO.ps1 | Vérifier format, encodage, séparateur des CSV/Excel | PS | RO | Lecture fichier | **P1** |

---

### 11 — QUALITÉ DES DONNÉES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_QD_01_Find_Duplicates_In_Table_RO.sql | Doublons sur une ou plusieurs colonnes (@TableName, @Keys) | SQL | RO | db_datareader | **P0** |
| SQL_QD_02_Check_Null_Coverage_RO.sql | % de NULL par colonne dans une table | SQL | RO | db_datareader | **P0** |
| SQL_QD_03_Find_Orphan_Foreign_Keys_RO.sql | Lignes orphelines sans parent (FK violée de fait) | SQL | RO | db_datareader | **P1** |
| SQL_QD_04_Compare_Table_Samples_RO.sql | Comparer un échantillon de lignes entre deux tables | SQL | RO | db_datareader | **P1** |
| SQL_QD_05_Find_Out_Of_Range_Values_RO.sql | Valeurs hors plage (@Col, @Min, @Max) | SQL | RO | db_datareader | **P1** |
| SQL_QD_06_Detect_Data_Type_Mismatches_RO.sql | Valeurs non convertibles dans une colonne VARCHAR | SQL | RO | db_datareader | **P1** |
| SQL_QD_07_Checksum_Table_RO.sql | Checksum d'une table pour comparer deux états | SQL | LR | db_datareader | P2 |

---

### 12 — WINDOWS SERVEUR

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| PS_WS_01_Get_Server_Resources_Snapshot_RO.ps1 | CPU, RAM totale/dispo, I/O disque — snapshot instantané | PS | RO | Lecteur local | **P0** |
| PS_WS_02_Monitor_CPU_Over_Time_RO.ps1 | CPU Windows toutes les N secondes pendant X minutes | PS | RO | Lecteur local | **P0** |
| PS_WS_03_Get_Top_Processes_By_CPU_RO.ps1 | Top processus par consommation CPU et RAM | PS | RO | Lecteur local | **P0** |
| PS_WS_04_Check_Disk_Space_Alert_RO.ps1 | Alerte si un disque dépasse X% d'utilisation | PS | RO | Lecteur local | **P0** |
| PS_WS_05_Check_SQLSERVER_Process_RO.ps1 | Mémoire et CPU consommés par le processus sqlservr.exe | PS | RO | Lecteur local | **P1** |
| PS_WS_06_Get_Event_Log_Errors_RO.ps1 | Erreurs récentes dans l'Event Log Windows | PS | RO | Lecteur EventLog | **P1** |
| PS_WS_07_Check_Network_Shares_RO.ps1 | Partages réseau accessibles, latence accès fichier | PS | RO | Lecteur réseau | **P1** |
| PS_WS_08_Get_SqlServer_Service_Status_RO.ps1 | Status des services SQL Server sur le serveur | PS | RO | Lecteur local | **P1** |

---

### 13 — FICHIERS LOGS ET CRE

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| PS_LC_01_Parse_DataStudio_Logs_RO.ps1 | Lire et filtrer les logs DATA STUDIO (erreurs, durées) | PS | RO | Lecture fichier | **P0** |
| PS_LC_02_Find_Errors_In_Logs_RO.ps1 | Extraire toutes les lignes ERROR/WARNING des logs | PS | RO | Lecture fichier | **P0** |
| PS_LC_03_Analyze_Log_Durations_RO.ps1 | Extraire et comparer les durées entre runs successifs | PS | RO | Lecture fichier | **P1** |
| PS_LC_04_Compare_Two_Log_Runs_RO.ps1 | Comparer deux fichiers de log (run N vs run N-1) | PS | RO | Lecture fichier | **P1** |
| PS_LC_05_Find_Incomplete_Treatments_RO.ps1 | Détecter traitements démarrés sans ligne de fin (crash) | PS | RO | Lecture fichier | **P1** |
| PS_LC_06_Get_Log_Summary_RO.ps1 | Résumé d'un log : nb étapes, nb erreurs, durée totale | PS | RO | Lecture fichier | **P1** |

---

### 14 — QUERY STORE (SQL Server 2016+)

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_QS_01_Find_Regressed_Queries_RO.sql | Requêtes dont les performances se sont dégradées | SQL | RO | VIEW DATABASE STATE | **P0** |
| SQL_QS_02_Get_Top_Resource_Consumers_RO.sql | Top N requêtes par CPU/IO/durée dans Query Store | SQL | RO | VIEW DATABASE STATE | **P0** |
| SQL_QS_03_Analyze_Plan_History_RO.sql | Historique des plans d'exécution d'une requête | SQL | RO | VIEW DATABASE STATE | **P1** |
| SQL_QS_04_Find_Forced_Plans_RO.sql | Plans actuellement forcés | SQL | RO | VIEW DATABASE STATE | **P1** |
| SQL_QS_05_Compare_Plans_For_Query_RO.sql | Comparer plusieurs plans pour une même requête | SQL | RO | VIEW DATABASE STATE | **P1** |
| SQL_QS_06_Force_Plan_MOD.sql | Forcer un plan d'exécution spécifique | SQL | MOD | ALTER DATABASE | P3 |
| SQL_QS_07_Check_QueryStore_Status_RO.sql | Vérifier que Query Store est activé et sa taille | SQL | RO | VIEW DATABASE STATE | **P1** |

---

### 15 — COMPARAISONS ET MESURES

| Nom fichier | Objectif | Tech | Risque | Permissions | Priorité |
|---|---|---|---|---|---|
| SQL_CM_01_Benchmark_Before_After_RO.sql | Template de mesure avant/après : IO, CPU, durée | SQL | LR | db_datareader | **P0** |
| SQL_CM_02_Compare_RowCounts_Two_Tables_RO.sql | Comparer le nombre de lignes de deux tables ou requêtes | SQL | RO | db_datareader | **P0** |
| SQL_CM_03_Measure_Query_Cost_RO.sql | Mesurer le coût exact d'une requête (IO, temps, plan) | SQL | LR | db_datareader | **P0** |
| SQL_CM_04_Compare_Index_Usage_Before_After_RO.sql | Comparer utilisation des index avant/après ajout | SQL | RO | VIEW SERVER STATE | **P1** |
| SQL_CM_05_Generate_Analysis_Report_RO.sql | Générer un rapport d'analyse condensé pour une session | SQL | RO | VIEW SERVER STATE | P2 |

---

## SECTION D — TOP 40 SCRIPTS PRIORITAIRES P0

*(Scripts à avoir opérationnels en premier — les plus utilisés quotidiennement dans ton contexte)*

| # | Nom fichier | Situation d'usage | Catégorie |
|---|---|---|---|
| 1 | SQL_DI_01_Get_Server_Health_RO.sql | Première chose à ouvrir face à n'importe quel problème | DI |
| 2 | SQL_DI_02_Get_WaitStats_RO.sql | Identifier en 30s le goulot principal (CPU/IO/Lock/réseau) | DI |
| 3 | SQL_DI_03_List_Running_Queries_RO.sql | Voir ce qui tourne en ce moment | DI |
| 4 | SQL_DI_04_Find_Long_Running_Queries_RO.sql | Script bloqué depuis hier — encore en vie ? | DI |
| 5 | SQL_DI_05_Check_Blocking_Now_RO.sql | Y a-t-il du blocking actif en ce moment ? | DI |
| 6 | PS_DI_01_Get_Server_Resources_Snapshot_RO.ps1 | Snapshot Windows instantané (CPU/RAM/Disk) | DI |
| 7 | SQL_SR_01_List_Active_Sessions_RO.sql | Qui est connecté, combien de sessions, depuis quand | SR |
| 8 | SQL_SR_03_Find_Blocking_Chain_RO.sql | Qui bloque qui (comme ton script d'hier) | SR |
| 9 | SQL_SR_04_Get_Query_Text_From_Session_RO.sql | Lire le SQL exact d'une session donnée | SR |
| 10 | SQL_PQ_01_Find_Top_Slow_Queries_CPU_RO.sql | Top N requêtes les plus coûteuses en CPU | PQ |
| 11 | SQL_PQ_02_Find_Top_Slow_Queries_IO_RO.sql | Top N requêtes les plus coûteuses en IO | PQ |
| 12 | SQL_PQ_03_Find_Top_Slow_Queries_Duration_RO.sql | Top N requêtes les plus longues | PQ |
| 13 | SQL_PQ_04_Analyze_Query_With_Stats_RO.sql | Mesurer IO+temps d'une requête fournie | PQ |
| 14 | SQL_PQ_05_Get_Execution_Plan_Cached_RO.sql | Lire le plan d'exécution depuis le cache | PQ |
| 15 | SQL_IX_01_Find_Missing_Indexes_RO.sql | Index manquants suggérés par SQL Server | IX |
| 16 | SQL_IX_02_List_Table_Indexes_RO.sql | Index d'une table — ce qui existe | IX |
| 17 | SQL_IX_03_Find_Unused_Indexes_RO.sql | Index jamais utilisés — candidats à la suppression | IX |
| 18 | SQL_IX_04_Check_Index_Fragmentation_RO.sql | Fragmentation — reorganize ou rebuild ? | IX |
| 19 | SQL_IX_05_Check_Statistics_Freshness_RO.sql | Stats obsolètes ? | IX |
| 20 | SQL_BL_01_Analyze_Current_Blocking_RO.sql | Analyse complète du blocking | BL |
| 21 | SQL_BL_03_Find_Deadlock_In_SystemHealth_RO.sql | Deadlocks récents dans l'historique | BL |
| 22 | SQL_MC_01_Check_Memory_Pressure_RO.sql | SQL Server en manque de mémoire ? | MC |
| 23 | SQL_MC_02_Check_CPU_Usage_RO.sql | CPU SQL Server vs OS | MC |
| 24 | SQL_MC_03_Analyze_IO_By_Database_RO.sql | Quelle base génère le plus d'IO | MC |
| 25 | SQL_MC_04_Check_Tempdb_Usage_RO.sql | Tempdb saturé ? Qui consomme ? | MC |
| 26 | SQL_FS_01_Analyze_Database_Files_RO.sql | Taille et état des fichiers (MDF/LDF) | FS |
| 27 | SQL_FS_02_Check_Log_File_Usage_RO.sql | Log file qui grossit — pourquoi ? | FS |
| 28 | PS_FS_01_Check_Disk_Space_All_Drives_RO.ps1 | Disque plein ? Espace restant ? | FS |
| 29 | SQL_OB_01_Inspect_Table_Structure_RO.sql | Structure d'une table inconnue | OB |
| 30 | SQL_OB_02_Get_Table_RowCount_Size_RO.sql | Nombre de lignes et taille d'une table | OB |
| 31 | SQL_OB_03_List_All_Tables_With_Sizes_RO.sql | Vue d'ensemble d'une base (toutes les tables) | OB |
| 32 | SQL_JA_01_List_Failed_Jobs_Last24h_RO.sql | Jobs ayant échoué cette nuit | JA |
| 33 | SQL_JA_02_Get_Job_History_RO.sql | Historique d'un job (durées, échecs) | JA |
| 34 | SQL_JA_03_List_Running_Jobs_RO.sql | Jobs en cours en ce moment | JA |
| 35 | SQL_ET_01_Compare_RowCounts_All_Layers_RO.sql | Volumes CRE→TFT→ODS→IC en un seul regard | ET |
| 36 | SQL_ET_02_Find_RowCount_Discrepancies_RO.sql | Où les lignes disparaissent dans la chaîne | ET |
| 37 | SQL_ET_05_Find_Orphan_Records_RO.sql | Lignes sans correspondance entre deux tables | ET |
| 38 | PS_ET_01_Check_CRE_Files_Status_RO.ps1 | Fichiers CRE présents, taille, date | ET |
| 39 | SQL_QD_01_Find_Duplicates_In_Table_RO.sql | Doublons dans une table (comme NOT IN hier) | QD |
| 40 | SQL_CM_01_Benchmark_Before_After_RO.sql | Mesurer l'impact d'une optimisation | CM |

---

## SECTION E — QUESTIONS TECHNIQUES NÉCESSAIRES

Pour construire des scripts **calibrés à ton environnement précis**, j'ai besoin de réponses à ces questions.

### Bloc 1 — SQL Server (obligatoire)

1. **Quelle version SQL Server** est utilisée sur le serveur de production ?
   ```sql
   SELECT @@VERSION;
   SELECT SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('Edition');
   ```

2. **Query Store est-il activé** sur les bases ODS et IC ?
   ```sql
   SELECT name, is_query_store_on FROM sys.databases;
   ```

3. **Quel niveau d'isolation est en vigueur** (RCSI activé ?) :
   ```sql
   SELECT name, is_read_committed_snapshot_on FROM sys.databases;
   ```

4. **SQL Server Agent est-il disponible et actif** sur le serveur ?

5. **Quels droits SQL as-tu** — sysadmin, db_owner, ou droits limités ?
   ```sql
   SELECT IS_SRVROLEMEMBER('sysadmin'), IS_SRVROLEMEMBER('serveradmin');
   ```

### Bloc 2 — Architecture et environnement

6. **Combien de serveurs SQL** sont impliqués dans la chaîne ? (TFT, ODS et IC sont-ils sur le même serveur ou des serveurs distincts ?)

7. **Existe-t-il des environnements distincts** DEV / TEST / PROD ?

8. **Peux-tu exécuter des scripts PowerShell** directement sur le serveur Windows (RDP) ou seulement depuis ton poste via SSMS ?

### Bloc 3 — ETL et DATA STUDIO

9. **Les logs DATA STUDIO** sont-ils des fichiers texte, CSV, XML, ou autre format ? Montre-moi un extrait de quelques lignes pour que je calibre le parser.

10. **Les tables TFT, ODS, IC** contiennent-elles des colonnes de date de chargement (ex : `DATE_CHARGEMENT`, `DATECREATION`, `MODIFIED_DATE`) ? C'est essentiel pour analyser la chronologie des traitements.

11. **Y a-t-il une table de log applicatif** dans SQL Server qui trace les exécutions DATA STUDIO (début, fin, nb lignes, statut) ?

### Bloc 4 — Volumes (pour calibrer les scripts)

12. **Quelle est la table la plus volumineuse** de l'environnement, et combien de lignes contient-elle approximativement ? (exemple : ODS_MOUVEMENTS_PERE avec ~39M lignes vu dans les captures)

13. **Combien de temps durent les traitements normalement** de bout en bout (CRE→IC) — quand tout va bien ?

---

## PROCHAINE ÉTAPE

Une fois tes réponses reçues, je passe en **PHASE 2** :
- Construction des scripts P0 un par un, avec code complet + documentation
- En commençant par le dossier `01_DIAGNOSTIC_INITIAL` (les scripts que tu dois ouvrir en premier face à n'importe quel incident)
- Puis `10_ETL_CHAINE_TRAITEMENT` (spécifique à ta chaîne CRE→TFT→ODS→IC)

Les scripts P0 seront opérationnels et paramétrables immédiatement.
