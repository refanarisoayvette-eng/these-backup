# Systeme de Sauvegarde et Restauration Automatise

Projet de these : conception d'un systeme automatise de sauvegarde, de restauration et de verification d'integrite d'une base de donnees PostgreSQL.

## Problematique

En cas de panne, d'erreur humaine ou d'attaque :
- Le serveur tombe en panne
- Une table est supprimee par erreur
- Un ransomware chiffre les donnees
- Un administrateur execute une mauvaise commande

**Question** : comment garantir la disponibilite, l'integrite et la recuperation des donnees ?

## Architecture

Trois conteneurs Docker :
- **postgres-prod** : PostgreSQL 16 avec WAL archiving active
- **backup-server** : serveur de sauvegarde (pg_dump, GPG, mc, cron)
- **minio** : stockage objet S3 local

## 4 piliers

1. **Automatisation** : sauvegarde quotidienne a 2h via cron
2. **Chiffrement** : GPG RSA 3072 bits
3. **Externalisation** : copie S3 (regle 3-2-1)
4. **WAL archiving** : RPO proche de 0

## Pipeline de sauvegarde (5 etapes)

1. pg_dump : dump compresse
2. Chiffrement GPG : fichier .dump.gpg
3. Checksum SHA-256 du fichier chiffre
4. Verification d'integrite
5. Envoi vers MinIO S3

## Taches planifiees (cron)

| Heure | Tache |
|-------|-------|
| 2h00 | backup.sh |
| 4h00 | cleanup.sh (GFS) |
| 5h00 dimanche | restore_test.sh |
| 6h00 | verify_backups.sh |
| chaque minute | archive_wal.sh |

## Politique de retention GFS

- 7 backups quotidiens
- 4 backups hebdomadaires
- 12 backups mensuels
- Safety minimum : 3 backups

## Resultats mesures

### RTO (test de restauration, 5 runs)
- Minimum : 3755 ms
- Maximum : 5404 ms
- Moyen : ~4683 ms

### Simulations de sinistre
| Scenario | RPO | RTO |
|----------|-----|-----|
| DROP TABLE | 0 | 2s |
| Corruption | 0 | 4s |
| Perte totale | 0 | 4s |

### WAL archiving
- Frequence : chaque minute
- RPO effectif : ~60 secondes

### Conformite regle 3-2-1
- 3 copies : Local + Hote + MinIO S3
- 2 supports : Disque local + Stockage objet
- 1 hors-site : MinIO externalisable

## Utilisation

Sauvegarde manuelle :
    docker exec -it backup-server bash /scripts/backup.sh

Verification integrite :
    docker exec -it backup-server bash /scripts/verify_backups.sh

PITR (restauration a un instant T) :
    docker exec -it backup-server bash /scripts/pitr_restore.sh "2026-09-29 12:00:00"

Simulation de sinistre :
    docker exec -it backup-server bash /scripts/simulate_disaster.sh A

Rapport complet :
    docker exec -it backup-server bash /scripts/generate_report.sh

Interface MinIO : http://localhost:9001 (minioadmin / minioadmin123)

## Structure

    these-backup/
    ├── README.md
    ├── configs/
    │   ├── docker-compose.yml
    │   ├── Dockerfile.backup
    │   └── init-backup.sh
    ├── scripts/
    │   ├── backup.sh
    │   ├── restore_test.sh
    │   ├── verify_backups.sh
    │   ├── archive_wal.sh
    │   ├── pitr_restore.sh
    │   ├── cleanup.sh
    │   ├── simulate_disaster.sh
    │   ├── generate_report.sh
    │   ├── notify.sh
    │   ├── measure_rto.sh
    │   ├── setup_cron.sh
    │   └── start_labo.sh
    ├── sql/
    │   ├── 01_schema.sql
    │   └── 02_data.sql
    ├── docs/
    │   ├── PITR.md
    │   └── ...
    ├── logs/
    └── backups/

## Auteur

Yvette Refanarisoa - 2026

Citation cle : "Une sauvegarde non testee n'est pas une sauvegarde."
