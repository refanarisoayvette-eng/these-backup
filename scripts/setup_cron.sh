#!/bin/bash
# ============================================
# INSTALLATION DES TÂCHES CRON
# ============================================

# Chemin du crontab
CRON_FILE="/etc/cron.d/these-backup"

cat > "$CRON_FILE" << 'CRON'
# ============================================
# THESE BACKUP - TÂCHES PLANIFIÉES
# ============================================
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Sauvegarde quotidienne à 2h00 du matin
0 2 * * * root /scripts/backup.sh >> /logs/cron-backup.log 2>&1

# Nettoyage des backups anciens (>7 jours) à 4h00
0 4 * * * root /scripts/cleanup.sh 7 >> /logs/cron-cleanup.log 2>&1

# Test de restauration chaque dimanche à 5h00
# 0 5 * * 0 root /scripts/restore_test.sh >> /logs/cron-restore.log 2>&1
CRON

chmod 644 "$CRON_FILE"
echo "✅ Tâches cron installées dans $CRON_FILE"
echo ""
echo "Contenu :"
cat "$CRON_FILE"
