#!/bin/bash
# ============================================
# SIMULATION DE SINISTRE + REPRISE
# ============================================
# Ce script :
#   1. Fait un backup frais (état connu)
#   2. Simule un sinistre
#   3. Mesure le RPO (données perdues)
#   4. Restaure depuis MinIO
#   5. Mesure le RTO (temps de reprise)
#   6. Vérifie la cohérence
# ============================================

set -euo pipefail

DB_HOST="postgres-prod"
DB_PORT="5432"
DB_USER="admin"
DB_PASSWORD="admin123"
DB_PROD="gestion_commerciale"

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"
WORK_DIR="/tmp/disaster_test"
LOG_FILE="/logs/disaster.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

export PGPASSWORD="$DB_PASSWORD"

# ---- CHOIX DU SCÉNARIO ----
SCENARIO="${1:-A}"

log ""
log "==============================================="
log "  SIMULATION DE SINISTRE - Scénario $SCENARIO"
log "==============================================="

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
rm -f *.gpg *.dump 2>/dev/null || true

# ---- ÉTAPE 1 : ÉTAT INITIAL ----
log ""
log "→ ÉTAPE 1 : État initial de la production"
COUNT_BEFORE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
              -tAc "SELECT COUNT(*) FROM clients;" 2>/dev/null)
log "   Clients en base : $COUNT_BEFORE"

# ---- ÉTAPE 2 : BACKUP FRAIS ----
log ""
log "→ ÉTAPE 2 : Création d'un backup frais (état de référence)"
/scripts/backup.sh > /dev/null 2>&1

# Récupérer le nom du dernier backup
LATEST=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | \
         grep "\.dump\.gpg$" | sort -k2 | tail -1 | awk '{print $NF}')
log "   Backup de référence : $LATEST"

# ---- ÉTAPE 3 : SINISTRE ----
log ""
log "→ ÉTAPE 3 : Déclenchement du sinistre (scénario $SCENARIO)"

DISASTER_TIME=$(date +%s)

case $SCENARIO in
    A)
        log "   💥 Suppression accidentelle de la table clients..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
            -c "DROP TABLE clients CASCADE;" > /dev/null 2>&1
        log "   ☠️  Table clients SUPPRIMÉE"
        ;;
    B)
        log "   💥 Corruption massive (UPDATE erroné)..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
            -c "UPDATE clients SET nom = 'CORROMPU';" > /dev/null 2>&1
        log "   ☠️  Tous les noms clients CORROMPUS"
        ;;
    C)
        log "   💥 Perte totale : DROP de toutes les tables..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
            -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" > /dev/null 2>&1
        log "   ☠️  Base de données ENTIÈREMENT PERDUE"
        ;;
    *)
        log "   ❌ Scénario inconnu : $SCENARIO"
        exit 1
        ;;
esac

# Vérifier la perte
COUNT_AFTER=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
             -tAc "SELECT COUNT(*) FROM clients;" 2>/dev/null || echo "0")
log "   Clients après sinistre : $COUNT_AFTER"

# ---- ÉTAPE 4 : REPRISE ----
log ""
log "→ ÉTAPE 4 : Lancement de la procédure de reprise"

RESTORE_START=$(date +%s)

# Télécharger le backup
log "   ↓ Téléchargement du backup..."
mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$LATEST" ./backup.dump.gpg > /dev/null 2>&1

# Déchiffrer
log "   🔓 Déchiffrement..."
gpg --batch --yes --decrypt backup.dump.gpg > backup.dump 2>/dev/null

# Restaurer (--clean écrase tout)
log "   🔄 Restauration en production..."
pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_PROD" --clean --if-exists --no-owner --no-privileges \
    backup.dump > /dev/null 2>&1 || true

RESTORE_END=$(date +%s)
RTO=$((RESTORE_END - RESTORE_START))

# ---- ÉTAPE 5 : VÉRIFICATION ----
log ""
log "→ ÉTAPE 5 : Vérification de la reprise"

COUNT_RESTORED=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_PROD" \
                -tAc "SELECT COUNT(*) FROM clients;" 2>/dev/null || echo "0")
log "   Clients après reprise : $COUNT_RESTORED"

# ---- RÉSULTAT ----
log ""
log "==============================================="
log "  RAPPORT DE REPRISE - Scénario $SCENARIO"
log "==============================================="
log "  RPO (données perdues) : $((COUNT_BEFORE - COUNT_RESTORED)) enregistrements"
log "  RTO (temps de reprise) : ${RTO} secondes"
log "  État avant  : $COUNT_BEFORE clients"
log "  État après  : $COUNT_RESTORED clients"

if [ "$COUNT_BEFORE" = "$COUNT_RESTORED" ]; then
    log "  ✅ REPRISE RÉUSSIE - Aucune perte"
else
    log "  ⚠️  Écart détecté entre avant et après"
fi
log "==============================================="

rm -f "$WORK_DIR"/*
