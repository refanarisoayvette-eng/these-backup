# Systeme de Sauvegarde et Restauration Automatise

Projet de these : conception d'un systeme automatise de sauvegarde, de restauration et de verification d'integrite d'une base de donnees.

## Problematique

En cas de panne, d'erreur humaine ou d'attaque :
- Le serveur tombe en panne
- Une table est supprimee par erreur
- Un ransomware chiffre les donnees
- Un administrateur execute une mauvaise commande

Question : comment garantir la disponibilite, l'integrite et la recuperation des donnees ?

## Architecture

Trois conteneurs Docker :
- postgres-prod : base de production PostgreSQL 16
- backup-server : serveur de sauvegarde avec pg_dump, GPG, mc, cron
- minio : stockage objet S3 local

## 3 piliers

1. Automatisation : sauvegarde quotidienne a 2h via cron
2. Chiffrement : GPG RSA 3072 bits
3. Externalisation : copie S3 (regle 3-2-1)

## Installation

    cd ~/these-backup
    cd configs && docker compose -f docker-compose.yml build backup-server && cd ..
    docker compose -f configs/docker-compose.yml up -d

## Utilisation

Sauvegarde manuelle :
    docker exec -it backup-server bash /scripts/backup.sh

Test de restauration :
    docker exec -it backup-server bash /scripts/restore_test.sh

Simulation de sinistre (A, B ou C) :
    docker exec -it backup-server bash /scripts/simulate_disaster.sh A

Rapport complet :
    docker exec -it backup-server bash /scripts/generate_report.sh

Interface MinIO : http://localhost:9001 (minioadmin / minioadmin123)

## Resultats mesures

Test de restauration :
- RTO mesure : 3 secondes
- Tables verifiees : 6/6
- Coherence prod/test : 100%

Simulations de sinistre :
- Scenario A (DROP TABLE) : RTO = 2s, RPO = 0
- Scenario B (corruption) : RTO = 4s, RPO = 0
- Scenario C (perte totale) : RTO = 4s, RPO = 0

Conformite regle 3-2-1 :
- 3 copies : Locale + Hote + MinIO
- 2 supports : Disque + Objet S3
- 1 hors-site : MinIO externalisable

## Structure du projet

    these-backup/
    ├── README.md
    ├── configs/
    │   ├── docker-compose.yml
    │   ├── Dockerfile.backup
    │   └── init-backup.sh
    ├── scripts/
    │   ├── backup.sh
    │   ├── restore_test.sh
    │   ├── cleanup.sh
    │   ├── simulate_disaster.sh
    │   ├── generate_report.sh
    │   └── setup_cron.sh
    ├── sql/
    │   ├── 01_schema.sql
    │   └── 02_data.sql
    ├── logs/
    ├── backups/
    └── docs/

## Auteur

Yvette Refanarisoa - 2026

Citation cle : "Une sauvegarde non testee n'est pas une sauvegarde."
# Test
