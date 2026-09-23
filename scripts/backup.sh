#!/bin/bash
# ============================================
# SCRIPT DE SAUVEGARDE POSTGRESQL COMPLET
# Dump + Checksum + Chiffrement GPG + Envoi S3 (MinIO)
# ============================================

set -euo pipefail

# ---- CONFIGURATION ----
DB_HOST="postgres-prod"
DB_PORT="5432"
DB_USER="admin"
DB_NAME="gestion_commerciale"
DB_PASSWORD="admin123"

BACKUP_DIR="/backups"
LOG_FILE="/logs/backup.log"
GPG_RECIPIENT="backup@entreprise.local"

# MinIO (stockage objet S3)
MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"

DATE=$(date +%Y%m%d_%H%M%S)
FILENAME="${DB_NAME}_${DATE}.dump"
FULLPATH="${BACKUP_DIR}/${FILENAME}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---- DÉBUT ----
log "==============================================="
log "DÉBUT SAUVEGARDE : $DB_NAME"
log "==============================================="

mkdir -p "$BACKUP_DIR"
export PGPASSWORD="$DB_PASSWORD"

# ---- 1. DUMP ----
START_TIME=$(date +%s)
log "→ 1/5 Lancement de pg_dump..."

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -Fc -f "$FULLPATH" "$DB_NAME"

SIZE_RAW=$(du -h "$FULLPATH" | cut -f1)
log "   ✅ Dump créé : $SIZE_RAW"

# ---- 2. CHECKSUM ----
log "→ 2/5 Calcul du checksum..."
sha256sum "$FULLPATH" > "${FULLPATH}.sha256"
log "   Checksum : $(cut -d' ' -f1 ${FULLPATH}.sha256)"

# ---- 3. CHIFFREMENT GPG ----
log "→ 3/5 Chiffrement GPG..."
gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" "$FULLPATH"
log "   ✅ Chiffré : ${FILENAME}.gpg"
rm -f "$FULLPATH"   # On ne garde que le .gpg chiffré
SIZE_GPG=$(du -h "${FULLPATH}.gpg" | cut -f1)
log "   Taille chiffrée : $SIZE_GPG"

# ---- 4. VÉRIFICATION INTÉGRITÉ ----
log "→ 4/5 Vérification de l'intégrité..."
if gpg --batch --list-packets "${FULLPATH}.gpg" > /dev/null 2>&1; then
    log "   ✅ Fichier GPG valide"
else
    log "   ❌ Fichier GPG corrompu"
    exit 4
fi

# ---- 5. ENVOI VERS MINIO (S3) ----
log "→ 5/5 Envoi vers MinIO..."
if mc cp "${FULLPATH}.gpg" "${MINIO_ALIAS}/${MINIO_BUCKET}/" >/dev/null 2>&1 && \
   mc cp "${FULLPATH}.sha256" "${MINIO_ALIAS}/${MINIO_BUCKET}/" >/dev/null 2>&1 ; then

    # Vérifier la taille côté distant
    REMOTE_SIZE=$(mc stat "${MINIO_ALIAS}/${MINIO_BUCKET}/${FILENAME}.gpg" 2>/dev/null | grep -i "size" | awk -F: '{print $2}' | tr -d ' ')
    log "   ✅ Copie envoyée vers s3://${MINIO_BUCKET}/"
    log "   Taille distante : ${REMOTE_SIZE}"
else
    log "   ⚠️  ÉCHEC envoi MinIO (le backup local reste valide)"
    # On ne sort pas en erreur : le backup local est là
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "✅ SAUVEGARDE RÉUSSIE"
log "   Fichier : ${FILENAME}.gpg"
log "   Durée   : ${DURATION} secondes"
log "FIN OK"
