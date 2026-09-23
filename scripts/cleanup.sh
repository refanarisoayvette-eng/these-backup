#!/bin/bash
# ============================================
# SCRIPT DE NETTOYAGE DES ANCIENNES SAUVEGARDES
# ============================================
# Politique : garder les backups des N derniers jours
# Usage : ./cleanup.sh [jours]
# ============================================

set -euo pipefail

BACKUP_DIR="/backups"
LOG_FILE="/logs/cleanup.log"
RETENTION_DAYS="${1:-7}"   # 7 jours par défaut

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "==============================================="
log "DÉBUT NETTOYAGE - Rétention : $RETENTION_DAYS jours"
log "==============================================="

# Compter avant
TOTAL_BEFORE=$(find "$BACKUP_DIR" -name "*.dump" | wc -l)
SIZE_BEFORE=$(du -sh "$BACKUP_DIR" | cut -f1)

log "→ Fichiers avant : $TOTAL_BEFORE ($SIZE_BEFORE)"

# Supprimer les .dump de plus de N jours
DELETED=0
while IFS= read -r file; do
    if [ -n "$file" ]; then
        log "   🗑️  Suppression : $(basename "$file")"
        rm -f "$file" "$file.sha256"
        DELETED=$((DELETED + 1))
    fi
done < <(find "$BACKUP_DIR" -name "*.dump" -mtime +"$RETENTION_DAYS")

# Compter après
TOTAL_AFTER=$(find "$BACKUP_DIR" -name "*.dump" | wc -l)
SIZE_AFTER=$(du -sh "$BACKUP_DIR" | cut -f1)

log "→ Fichiers supprimés : $DELETED"
log "→ Fichiers après    : $TOTAL_AFTER ($SIZE_AFTER)"
log "FIN NETTOYAGE"
