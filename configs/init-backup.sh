#!/bin/bash
# ============================================
# INITIALISATION DU SERVEUR DE SAUVEGARDE
# ============================================
set -e

echo "[init] Démarrage du serveur de sauvegarde..."

# 1. Génération de la clé GPG (si absente)
mkdir -p /root/.gnupg && chmod 700 /root/.gnupg

if ! gpg --list-keys backup@entreprise.local > /dev/null 2>&1; then
    echo "[init] Génération de la clé GPG..."
    gpg --batch --generate-key << GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: Backup Server
Name-Email: backup@entreprise.local
Expire-Date: 0
%commit
GPGEOF
    echo "[init] ✅ Clé GPG créée"
else
    echo "[init] ✅ Clé GPG déjà présente"
fi

# 2. Démarrage de cron
service cron start > /dev/null 2>&1 || true
echo "[init] ✅ Cron démarré"

# 3. Maintien du conteneur en vie
echo "[init] Container prêt."
exec sleep infinity
