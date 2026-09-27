#!/bin/bash
# ============================================
# NETTOYAGE GFS + SAFETY MINIMUM
# ============================================

set -uo pipefail

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"
LOG_FILE="/logs/cleanup.log"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
SAFETY_MIN=3   # Ne jamais descendre sous ce nombre de backups

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "==============================================="
log "NETTOYAGE GFS"
log "==============================================="

mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | grep "\.dump\.gpg$" | awk '{print $NF}' | sort > /tmp/all_backups.txt
TOTAL=$(wc -l < /tmp/all_backups.txt)
log "Total backups existants : $TOTAL"

if [ "$TOTAL" -le "$SAFETY_MIN" ]; then
    log "SAFETY : Seulement $TOTAL backups, aucun nettoyage effectue"
    rm -f /tmp/all_backups.txt
    /scripts/notify.sh SUCCESS "Nettoyage GFS : conserve (safety minimum)"
    exit 0
fi

declare -A KEEP
TODAY=$(date +%Y%m%d)

# 1. Quotidiens
log ""
log "-> 1/3 Quotidiens : $KEEP_DAILY derniers"
C=0
for i in $(seq 0 $((KEEP_DAILY - 1))); do
    D=$(date -d "$TODAY - $i day" +%Y%m%d)
    M=$(grep "_${D}_" /tmp/all_backups.txt | tail -1 || true)
    [ -n "$M" ] && { KEEP["$M"]=1; log "   [J-$i] $M"; C=$((C+1)); }
done
log "   Total quotidiens : $C"

# 2. Hebdomadaires
log ""
log "-> 2/3 Hebdomadaires : $KEEP_WEEKLY derniers dimanches"
C=0
for i in $(seq 1 $((KEEP_WEEKLY * 7))); do
    D=$(date -d "$TODAY - $i day" +%Y%m%d)
    DW=$(date -d "$TODAY - $i day" +%u)
    if [ "$DW" = "7" ]; then
        M=$(grep "_${D}_" /tmp/all_backups.txt | tail -1 || true)
        if [ -n "$M" ] && [ -z "${KEEP[$M]:-}" ]; then
            KEEP["$M"]=1; log "   [S-$C] $M"; C=$((C+1))
        fi
    fi
    [ "$C" -ge "$KEEP_WEEKLY" ] && break
done
log "   Total hebdomadaires : $C"

# 3. Mensuels
log ""
log "-> 3/3 Mensuels : $KEEP_MONTHLY derniers mois"
C=0
for i in $(seq 0 "$KEEP_MONTHLY"); do
    D=$(date -d "$TODAY - $i month" +%Y%m)
    M=$(grep "_${D}" /tmp/all_backups.txt | sort | head -1 || true)
    if [ -n "$M" ] && [ -z "${KEEP[$M]:-}" ]; then
        KEEP["$M"]=1; log "   [M-$i] $M"; C=$((C+1))
    fi
done
log "   Total mensuels : $C"

# Safety : s'assurer que le dernier backup est toujours conserve
LATEST=$(tail -1 /tmp/all_backups.txt)
KEEP["$LATEST"]=1

# Suppression
log ""
log "-> Suppression des backups non retenus..."
NB_KEEP=${#KEEP[@]}
NB_DELETE=0

while IFS= read -r B; do
    if [ -z "${KEEP[$B]:-}" ]; then
        log "   Suppression : $B"
        mc rm "$MINIO_ALIAS/$MINIO_BUCKET/$B" > /dev/null 2>&1
        mc rm "$MINIO_ALIAS/$MINIO_BUCKET/$B.sha256" > /dev/null 2>&1
        NB_DELETE=$((NB_DELETE + 1))
    fi
done < /tmp/all_backups.txt

rm -f /tmp/all_backups.txt

log ""
log "==============================================="
log "RESULTAT GFS"
log "  Conservés : $NB_KEEP"
log "  Supprimés : $NB_DELETE"
log "==============================================="

/scripts/notify.sh SUCCESS "Nettoyage GFS : $NB_KEEP conserves, $NB_DELETE supprimes"
