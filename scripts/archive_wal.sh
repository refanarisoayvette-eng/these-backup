#!/bin/bash
# ============================================
# ARCHIVAGE CONTINU DES WAL VERS MINIO
# (avec filtre sur le format WAL valide)
# ============================================
set -uo pipefail

MINIO_ALIAS="minio"
MINIO_BUCKET="wal-archive"
WAL_SOURCE="/wal_archive"
LOG_FILE="/logs/wal_archive.log"
WAL_REGEX="^[0-9A-F]{24}$"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

if ! mc alias list 2>/dev/null | grep -q "$MINIO_ALIAS"; then
    mc alias set "$MINIO_ALIAS" http://minio:9000 minioadmin minioadmin123 > /dev/null 2>&1
fi

mc mb "$MINIO_ALIAS/$MINIO_BUCKET" > /dev/null 2>&1 || true

if [ ! -d "$WAL_SOURCE" ]; then
    log "ERREUR : dossier $WAL_SOURCE introuvable"
    exit 1
fi

TOTAL=0
UPLOADED=0
FAILED=0
SKIPPED=0
INVALID=0

for WAL_FILE in "$WAL_SOURCE"/*; do
    [ ! -f "$WAL_FILE" ] && continue

    FILENAME=$(basename "$WAL_FILE")
    TOTAL=$((TOTAL + 1))

    # Filtrer : uniquement les vrais WAL (24 car hexa)
    if ! echo "$FILENAME" | grep -qE "$WAL_REGEX"; then
        INVALID=$((INVALID + 1))
        continue
    fi

    if mc stat "$MINIO_ALIAS/$MINIO_BUCKET/$FILENAME" > /dev/null 2>&1; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if mc cp "$WAL_FILE" "$MINIO_ALIAS/$MINIO_BUCKET/" > /dev/null 2>&1; then
        UPLOADED=$((UPLOADED + 1))
    else
        FAILED=$((FAILED + 1))
        log "   ERREUR upload : $FILENAME"
    fi
done

log "   Total : $TOTAL | Uploades : $UPLOADED | Skips : $SKIPPED | Invalides : $INVALID | Echecs : $FAILED"

if [ "$UPLOADED" -gt 0 ]; then
    TOTAL_REMOTE=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | wc -l)
    /scripts/notify.sh SUCCESS "WAL archive : $UPLOADED nouveaux (total : $TOTAL_REMOTE)"
fi
