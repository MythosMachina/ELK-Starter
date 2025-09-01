#!/usr/bin/env bash
set -euo pipefail

# --- Root-Check ---
if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo/root ausführen."
  exit 1
fi

# --- OS-Erkennung (Debian/Ubuntu) ---
. /etc/os-release
if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
  echo "Dieses Provisioning-Script unterstützt offiziell Debian/Ubuntu."
  echo "Passe ggf. die Docker-Installation für deine Distribution an."
fi

# --- Pakete & Docker installieren ---
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/${ID}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/${ID} \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# --- Kernel-Tuning für Elasticsearch ---
# vm.max_map_count muss >= 262144 sein
sysctl -w vm.max_map_count=262144
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

# --- Verzeichnisstruktur anlegen & Rechte setzen ---
mkdir -p /mnt/elastic_logs/elasticsearch/{config,data,logs}
mkdir -p /mnt/elastic_logs/kibana/{config,logs}
mkdir -p /mnt/elastic_logs/fleet-server/{agent,logs}

# UID/GID 1000 ist Standard in Elastic/Kibana-Container
chown -R 1000:1000 /mnt/elastic_logs/elasticsearch
chown -R 1000:1000 /mnt/elastic_logs/kibana
# Fleet Server (Elastic Agent) läuft oft als root im Container:
chown -R 0:0 /mnt/elastic_logs/fleet-server || true

chmod -R 0775 /mnt/elastic_logs

echo "Provisionierung abgeschlossen."
docker --version
docker compose version
