#!/bin/bash
# ============================================
# MESURE DU RTO RÉEL (répété 5 fois)
# Version sans bc (utilise awk)
# ============================================
set -euo pipefail

DB_HOST="postgres-prod"
DB_PORT="5432"
DB_USER="admin"
DB_PASSWORD="admin123"
DB_PROD="gestion_commerciale"
DB_TEST="gestion_commerciale_test"

MINIO_ALIAS="minio"
MINIO_BUCKET="backups-postgres"
LOG_FILE="/logs/rto_mesures.log"
WORK_DIR="/tmp/rto_test"

export PGPASSWORD="$DB_PASSWORD"

echo "=============================================" | tee -a "$LOG_FILE"
echo "MESURE RTO - $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"

mkdir -p "$WORK_DIR"
NB_RUNS=5

# S'assurer qu'on a un backup récent
/scripts/backup.sh > /dev/null 2>&1

# Récupérer le dernier backup
LATEST=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" | grep "\.dump\.gpg$" | sort -k2 | tail -1 | awk '{print $NF}')
echo "Backup utilisé : $LATEST" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Tableau pour stocker les RTO
RTO_LIST=""

for i in $(seq 1 $NB_RUNS); do
    echo "--- Run $i/$NB_RUNS ---" | tee -a "$LOG_FILE"

    cd "$WORK_DIR"
    rm -f *.gpg *.dump 2>/dev/null || true

    # DÉBUT CHRONO (millisecondes)
    START=$(date +%s%3N)

    # 1. Télécharger
    mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$LATEST" ./b.dump.gpg > /dev/null 2>&1

    # 2. Déchiffrer
    gpg --batch --yes --decrypt b.dump.gpg > b.dump 2>/dev/null

    # 3. Drop + recreate
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $DB_TEST;" > /dev/null 2>&1
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE $DB_TEST;" > /dev/null 2>&1

    # 4. Restaurer
    pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
        -d "$DB_TEST" --no-owner --no-privileges b.dump > /dev/null 2>&1 || true

    # 5. Vérifier
    COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_TEST" \
        -tAc "SELECT COUNT(*) FROM clients;" 2>/dev/null)

    # FIN CHRONO
    END=$(date +%s%3N)
    RTO_MS=$((END - START))

    echo "  Clients restaurés : $COUNT" | tee -a "$LOG_FILE"
    echo "  RTO mesuré        : ${RTO_MS} ms" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    RTO_LIST="$RTO_LIST $RTO_MS"
done

# Nettoyage
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_TEST;" > /dev/null 2>&1
rm -f "$WORK_DIR"/*

# Calcul des stats avec awk
STATS=$(echo "$RTO_LIST" | awk '{
    min=$1; max=$1; sum=0; n=0;
    for (i=1; i<=NF; i++) {
        if ($i < min) min=$i;
        if ($i > max) max=$i;
        sum+=$i; n++;
    }
    printf "%d %d %.0f", min, max, sum/n
}')

RTO_MIN=$(echo $STATS | cut -d' ' -f1)
RTO_MAX=$(echo $STATS | cut -d' ' -f2)
RTO_MOY=$(echo $STATS | cut -d' ' -f3)

echo "=============================================" | tee -a "$LOG_FILE"
echo "RÉSULTATS ($NB_RUNS runs)" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "  RTO minimum : ${RTO_MIN} ms" | tee -a "$LOG_FILE"
echo "  RTO maximum : ${RTO_MAX} ms" | tee -a "$LOG_FILE"
echo "  RTO moyen   : ${RTO_MOY} ms" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
