#!/bin/bash
# ============================================
# INSTALLATION DES TACHES CRON
# ============================================

CRON_FILE="/etc/cron.d/these-backup"

cat > "$CRON_FILE" << 'CRON'
# ============================================
# THESE BACKUP - TACHES PLANIFIEES
# ============================================
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 1. Sauvegarde quotidienne a 2h00
0 2 * * * root /scripts/backup.sh >> /logs/cron-backup.log 2>&1

# 2. Nettoyage GFS a 4h00
0 4 * * * root /scripts/cleanup.sh >> /logs/cron-cleanup.log 2>&1

# 3. Test de restauration le dimanche a 5h00
0 5 * * 0 root /scripts/restore_test.sh >> /logs/cron-restore.log 2>&1

# 4. Verification d'integrite quotidienne a 6h00
0 6 * * * root /scripts/verify_backups.sh >> /logs/cron-verify.log 2>&1
CRON

chmod 644 "$CRON_FILE"
echo "Taches cron installees dans $CRON_FILE"
cat "$CRON_FILE"
