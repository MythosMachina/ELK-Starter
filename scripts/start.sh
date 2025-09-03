#!/usr/bin/env bash

set -euo pipefail

# Always execute from repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Clean and load environment variables
ENV_FILE="${ROOT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo ".env file is missing" >&2
  exit 1
fi

# Remove existing Kibana service token and any stray lines
grep -Ev '^KIBANA_SERVICE_TOKEN=' "${ENV_FILE}" | \
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=.*|^#|^$' > "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "${ENV_FILE}"

set -a
 # shellcheck source=/dev/null
 source "${ENV_FILE}"
set +a

# Ensure certificate files are readable inside the container
if [[ -d certs ]]; then
  find certs -type f -name '*.key' -exec chown root:root {} \; -exec chmod 660 {} \;
  find certs -type f -name '*.crt' -exec chown root:root {} \; -exec chmod 644 {} \;
fi

echo "[1/3] Start Elasticsearch and Caddy"
docker compose up -d es01 caddy

echo "[2/3] Waiting for Elasticsearch to respond"
until docker exec es01 curl -s --cacert /usr/share/elasticsearch/config/certs/ca.crt \
    -u elastic:"$ELASTIC_PASSWORD" https://localhost:9200 >/dev/null 2>&1; do
  sleep 2
done

echo "[3/3] Refresh Kibana service account token"
# Delete existing token if present to avoid 'token already exists' errors
docker exec es01 bin/elasticsearch-service-tokens delete elastic/kibana kibana >/dev/null 2>&1 || true
TOKEN=$(docker exec es01 bin/elasticsearch-service-tokens create elastic/kibana kibana | tail -n 1)
printf '\nKIBANA_SERVICE_TOKEN=%s\n' "$TOKEN" >> "$ENV_FILE"

export KIBANA_SERVICE_TOKEN="$TOKEN"
docker compose up -d

echo "Stack is running. Kibana service token stored in .env"

