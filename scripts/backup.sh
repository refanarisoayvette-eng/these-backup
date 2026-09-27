#!/bin/bash
# ============================================
# SCRIPT DE SAUVEGARDE POSTGRESQL COMPLET
# Dump + Chiffrement GPG + Checksum + Envoi S3
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

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"

DATE=$(date +%Y%m%d_%H%M%S)
FILENAME="${DB_NAME}_${DATE}.dump"
FULLPATH="${BACKUP_DIR}/${FILENAME}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---- DEBUT ----
log "==============================================="
log "DEBUT SAUVEGARDE : $DB_NAME"
log "==============================================="

mkdir -p "$BACKUP_DIR"
export PGPASSWORD="$DB_PASSWORD"

# ---- 1. DUMP ----
START_TIME=$(date +%s)
log "-> 1/5 Lancement de pg_dump..."

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -Fc -f "$FULLPATH" "$DB_NAME"

SIZE_RAW=$(du -h "$FULLPATH" | cut -f1)
log "   OK - Dump cree : $SIZE_RAW"

# ---- 2. CHIFFREMENT GPG ----
log "-> 2/5 Chiffrement GPG..."
gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" "$FULLPATH"
log "   OK - Chiffre : ${FILENAME}.gpg"
rm -f "$FULLPATH"
SIZE_GPG=$(du -h "${FULLPATH}.gpg" | cut -f1)
log "   Taille chiffree : $SIZE_GPG"

# ---- 3. CHECKSUM (du fichier chiffre .gpg) ----
log "-> 3/5 Calcul du checksum du fichier chiffre..."
sha256sum "${FULLPATH}.gpg" > "${FULLPATH}.gpg.sha256"
log "   Checksum : $(cut -d' ' -f1 ${FULLPATH}.gpg.sha256)"

# ---- 4. VERIFICATION INTEGRITE ----
log "-> 4/5 Verification de l'integrite..."
if gpg --batch --list-packets "${FULLPATH}.gpg" > /dev/null 2>&1; then
    log "   OK - Fichier GPG valide"
else
    log "   ERREUR - Fichier GPG corrompu"
    /scripts/notify.sh FAILURE "Backup echoue : fichier GPG corrompu"
    exit 4
fi

# ---- 5. ENVOI VERS MINIO ----
log "-> 5/5 Envoi vers MinIO..."
if mc cp "${FULLPATH}.gpg" "${MINIO_ALIAS}/${MINIO_BUCKET}/" >/dev/null 2>&1 && \
   mc cp "${FULLPATH}.gpg.sha256" "${MINIO_ALIAS}/${MINIO_BUCKET}/" >/dev/null 2>&1 ; then
    log "   OK - Copie envoyee vers s3://${MINIO_BUCKET}/"
    REMOTE_SIZE=$(mc stat "${MINIO_ALIAS}/${MINIO_BUCKET}/${FILENAME}.gpg" 2>/dev/null | grep -i "size" | awk -F: '{print $2}' | tr -d ' ')
    log "   Taille distante : ${REMOTE_SIZE}"
else
    log "   AVERTISSEMENT - Echec envoi MinIO (backup local conserve)"
    /scripts/notify.sh WARNING "Backup local OK mais envoi MinIO echoue"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "OK - SAUVEGARDE REUSSIE"
log "   Fichier : ${FILENAME}.gpg"
log "   Duree   : ${DURATION} secondes"
log "FIN OK"

# Notification Discord
/scripts/notify.sh SUCCESS "Sauvegarde reussie - Fichier: ${FILENAME}.gpg - Taille: ${SIZE_GPG} - Duree: ${DURATION}s"
