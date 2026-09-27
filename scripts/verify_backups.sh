#!/bin/bash
# ============================================
# VÉRIFICATION D'INTÉGRITÉ DES BACKUPS
# Version avec mc cp + fichier temporaire
# ============================================

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"
WORK_DIR="/tmp/verify"
LOG_FILE="/logs/verify_backups.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "==============================================="
log "VERIFICATION D'INTEGRITE DES BACKUPS"
log "==============================================="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
rm -f * 2>/dev/null || true

# S'assurer que l'alias existe
if ! mc alias list 2>/dev/null | grep -q "$MINIO_ALIAS"; then
    mc alias set "$MINIO_ALIAS" http://minio:9000 minioadmin minioadmin123 > /dev/null 2>&1
fi

# Recuperer la liste des .sha256
log "-> Liste des backups..."
mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | grep "\.sha256$" | awk '{print $NF}' > /tmp/sha_list.txt

NB=$(wc -l < /tmp/sha_list.txt)
log "   $NB fichier(s) .sha256 trouve(s)"
log ""

if [ "$NB" -eq 0 ]; then
    log "Aucun fichier a verifier"
    exit 1
fi

TOTAL=0
OK=0
CORRUPTED=0
MISSING=0

while IFS= read -r SHA_FILE || [ -n "$SHA_FILE" ]; do
    if [ -z "$SHA_FILE" ]; then continue; fi

    DUMP_FILE="${SHA_FILE%.sha256}"
    TOTAL=$((TOTAL + 1))

    log "-> $DUMP_FILE"

    # Telecharger le .sha256
    if ! mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$SHA_FILE" "./$SHA_FILE" > /dev/null 2>&1; then
        log "   Impossible de recuperer le .sha256"
        MISSING=$((MISSING + 1))
        continue
    fi

    # Telecharger le .dump.gpg
    if ! mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$DUMP_FILE" "./$DUMP_FILE" > /dev/null 2>&1; then
        log "   Impossible de recuperer le .dump.gpg"
        rm -f "./$SHA_FILE"
        MISSING=$((MISSING + 1))
        continue
    fi

    # Verifier la taille (doit etre > 0)
    SIZE=$(stat -c%s "./$DUMP_FILE")
    if [ "$SIZE" -eq 0 ]; then
        log "   Fichier vide (0 octet)"
        rm -f "./$SHA_FILE" "./$DUMP_FILE"
        CORRUPTED=$((CORRUPTED + 1))
        continue
    fi

    # Calculer les empreintes
    EXPECTED=$(cut -d' ' -f1 "./$SHA_FILE")
    ACTUAL=$(sha256sum "./$DUMP_FILE" | cut -d' ' -f1)

    if [ "$EXPECTED" = "$ACTUAL" ]; then
        log "   OK - Integre ($SIZE octets)"
        OK=$((OK + 1))
    else
        log "   CORROMPU !"
        log "      Attendu : $EXPECTED"
        log "      Obtenu  : $ACTUAL"
        CORRUPTED=$((CORRUPTED + 1))
    fi

    rm -f "./$SHA_FILE" "./$DUMP_FILE"
done < /tmp/sha_list.txt

rm -f /tmp/sha_list.txt "$WORK_DIR"/* 2>/dev/null || true

log ""
log "==============================================="
log "RESULTAT : $OK/$TOTAL integres"
if [ $CORRUPTED -gt 0 ]; then log "$CORRUPTED CORROMPU(S) !"; fi
if [ $MISSING -gt 0 ]; then log "$MISSING MANQUANT(S) !"; fi
log "==============================================="

# Notification Discord
if [ $CORRUPTED -gt 0 ] || [ $MISSING -gt 0 ]; then
    /scripts/notify.sh FAILURE "Verification : $OK/$TOTAL integres, $CORRUPTED corrompus, $MISSING manquants"
else
    /scripts/notify.sh SUCCESS "Verification : $OK/$TOTAL integres"
fi
