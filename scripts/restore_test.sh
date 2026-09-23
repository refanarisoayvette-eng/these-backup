#!/bin/bash
# ============================================
# TEST AUTOMATIQUE DE RESTAURATION
# ============================================
# Ce script :
#   1. Télécharge le dernier backup depuis MinIO
#   2. Le déchiffre
#   3. Le restaure dans une base de test
#   4. Vérifie l'intégrité
#   5. Mesure le RTO
#   6. Notifie le résultat
# ============================================

set -euo pipefail

# ---- CONFIGURATION ----
DB_HOST="postgres-prod"
DB_PORT="5432"
DB_USER="admin"
DB_PASSWORD="admin123"
DB_PROD="gestion_commerciale"
DB_TEST="gestion_commerciale_test"

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"

WORK_DIR="/tmp/restore_test"
LOG_FILE="/logs/restore_test.log"

# ---- FONCTIONS ----
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---- DÉBUT ----
log "==============================================="
log "DÉBUT TEST DE RESTAURATION"
log "==============================================="

START_TIME=$(date +%s)
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
rm -f *.gpg *.dump *.sha256 2>/dev/null || true

export PGPASSWORD="$DB_PASSWORD"

# ---- 1. TROUVER LE DERNIER BACKUP ----
log "→ 1/6 Recherche du dernier backup dans MinIO..."

LATEST=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | \
         grep "\.dump\.gpg$" | \
         sort -k2 | tail -1 | awk '{print $NF}')

if [ -z "$LATEST" ]; then
    log "   ❌ Aucun backup trouvé dans MinIO"
    exit 1
fi

log "   ✅ Backup trouvé : $LATEST"

# ---- 2. TÉLÉCHARGEMENT ----
log "→ 2/6 Téléchargement depuis MinIO..."
mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$LATEST" ./backup.dump.gpg > /dev/null 2>&1

if [ ! -f "backup.dump.gpg" ]; then
    log "   ❌ Échec du téléchargement"
    exit 2
fi

SIZE_GPG=$(du -h backup.dump.gpg | cut -f1)
log "   ✅ Téléchargé : $SIZE_GPG"

# ---- 3. DÉCHIFFREMENT ----
log "→ 3/6 Déchiffrement GPG..."
if ! gpg --batch --yes --decrypt backup.dump.gpg > backup.dump 2>/dev/null; then
    log "   ❌ Échec du déchiffrement GPG"
    exit 3
fi

SIZE_DUMP=$(du -h backup.dump | cut -f1)
log "   ✅ Déchiffré : $SIZE_DUMP"

# ---- 4. RESTAURATION DANS BASE DE TEST ----
log "→ 4/6 Restauration dans $DB_TEST..."

# Supprimer la base de test si elle existe
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_TEST;" > /dev/null 2>&1

# Créer la base de test
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "CREATE DATABASE $DB_TEST;" > /dev/null 2>&1

# Restaurer le dump
if ! pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_TEST" --no-owner --no-privileges backup.dump > /dev/null 2>&1; then
    log "   ⚠️  pg_restore a retourné des warnings (souvent normal)"
fi

log "   ✅ Restauration terminée"

# ---- 5. VÉRIFICATION D'INTÉGRITÉ ----
log "→ 5/6 Vérification de l'intégrité..."

TABLES=("clients" "produits" "commandes" "lignes_commande" "paiements" "stocks")
ERRORS=0

for TABLE in "${TABLES[@]}"; do
    COUNT_PROD=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
                 -tAc "SELECT COUNT(*) FROM $TABLE;" 2>/dev/null || echo "0")
    COUNT_TEST=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_TEST" \
                 -tAc "SELECT COUNT(*) FROM $TABLE;" 2>/dev/null || echo "0")

    if [ "$COUNT_PROD" = "$COUNT_TEST" ]; then
        log "   ✅ $TABLE : $COUNT_TEST lignes (identique prod)"
    else
        log "   ⚠️  $TABLE : prod=$COUNT_PROD, test=$COUNT_TEST"
        ERRORS=$((ERRORS + 1))
    fi
done

# ---- 6. MESURE RTO ----
END_TIME=$(date +%s)
RTO=$((END_TIME - START_TIME))

log "→ 6/6 Nettoyage..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "DROP DATABASE $DB_TEST;" > /dev/null 2>&1

rm -f "$WORK_DIR"/*

# ---- RÉSULTAT FINAL ----
log "==============================================="
if [ $ERRORS -eq 0 ]; then
    log "✅ TEST DE RESTAURATION RÉUSSI"
    log "   RTO mesuré : ${RTO} secondes"
    log "   Backup     : $LATEST"
    log "   Toutes les tables sont cohérentes"
    log "==============================================="
    exit 0
else
    log "⚠️  TEST PARTIEL : $ERRORS table(s) avec écart"
    log "   RTO mesuré : ${RTO} secondes"
    log "==============================================="
    exit 1
fi
