#!/bin/bash
set -e
echo "🚀 Démarrage du labo..."
sudo systemctl start docker 2>/dev/null || sudo service docker start
sleep 3
cd ~/these-backup
docker compose -f configs/docker-compose.yml up -d
sleep 15
docker exec -it backup-server service cron start 2>/dev/null || true
echo ""
echo "✅ Labo opérationnel !"
docker ps --format "table {{.Names}}\t{{.Status}}"
