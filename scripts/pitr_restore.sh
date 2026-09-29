#!/bin/bash
# ============================================
# RESTAURATION POINT-IN-TIME (PITR) - v1
# Usage : pitr_restore.sh "YYYY-MM-DD HH:MM:SS"
# ============================================
set -uo pipefail

TARGET_TIME="${1:-}"

if [ -z "$TARGET_TIME" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    exit 1
fi

DB_HOST="postgres-prod"
DB_PORT="5432"
DB_USER="admin"
DB_PASSWORD="admin123"
DB_TARGET="gestion_commerciale_pitr"

MINIO_ALIAS="minio"
MINIO_BACKUP_BUCKET="backups-postgres"
MINIO_WAL_BUCKET="wal-archive"
WORK_DIR="/tmp/pitr"
LOG_FILE="/logs/pitr.log"

export PGPASSWORD="$DB_PASSWORD"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "==============================================="
log "RESTAURATION PITR vers $TARGET_TIME"
log "==============================================="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
rm -f * 2>/dev/null || true

# 1. Convertir la date cible
TARGET_TS=$(date -d "$TARGET_TIME" +%Y%m%d_%H%M%S 2>/dev/null)
if [ -z "$TARGET_TS" ]; then
    log "ERREUR : date invalide '$TARGET_TIME'"
    exit 1
fi
log "-> Cible : $TARGET_TS"

# 2. Trouver le dernier dump disponible
log "-> Recherche du pg_dump le plus recent..."
LATEST_DUMP=$(mc ls "$MINIO_ALIAS/$MINIO_BACKUP_BUCKET/" 2>/dev/null | \
    grep "\.dump\.gpg$" | \
    awk '{print $NF}' | \
    sort | tail -1)

if [ -z "$LATEST_DUMP" ]; then
    log "ERREUR : aucun dump trouve"
    exit 2
fi
log "   Dump : $LATEST_DUMP"

# 3. Telecharger et dechiffrer
log "-> Telechargement et dechiffrement..."
mc cp "$MINIO_ALIAS/$MINIO_BACKUP_BUCKET/$LATEST_DUMP" ./base.dump.gpg > /dev/null 2>&1

if [ ! -f base.dump.gpg ]; then
    log "ERREUR : telechargement echoue"
    exit 3
fi

gpg --batch --yes --decrypt base.dump.gpg > base.dump 2>/dev/null

if [ ! -f base.dump ]; then
    log "ERREUR : dechiffrement echoue"
    exit 4
fi

log "   Taille : $(du -h base.dump | cut -f1)"

# 4. Restaurer dans la base cible
log "-> Restauration dans $DB_TARGET..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_TARGET;" > /dev/null 2>&1
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "CREATE DATABASE $DB_TARGET;" > /dev/null 2>&1

pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_TARGET" --no-owner --no-privileges base.dump > /dev/null 2>&1 || true

COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_TARGET" \
    -tAc "SELECT COUNT(*) FROM clients;" 2>/dev/null)

# 5. Resume
log ""
log "==============================================="
log "PITR TERMINE"
log "   Cible    : $TARGET_TIME"
log "   Base     : $DB_TARGET"
log "   Dump     : $LATEST_DUMP"
log "   Clients  : $COUNT"
log "==============================================="

/scripts/notify.sh SUCCESS "PITR : base $DB_TARGET restauree ($COUNT clients)"
