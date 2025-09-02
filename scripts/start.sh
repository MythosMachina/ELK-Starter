#!/usr/bin/env bash

set -euo pipefail

# Always execute from repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Load environment variables
source .env

# Remove any stale Kibana service token from previous runs
sed -i '/^KIBANA_SERVICE_TOKEN=/d' .env

echo "[1/3] Start Elasticsearch"
docker compose up -d es01

echo "[2/3] Waiting for Elasticsearch to respond"
until curl -s -u elastic:"$ELASTIC_PASSWORD" http://localhost:9200 >/dev/null 2>&1; do
  sleep 2
done

echo "[3/3] Refresh Kibana service account token"
# Delete existing token if present to avoid 'token already exists' errors
docker exec es01 bin/elasticsearch-service-tokens delete elastic/kibana kibana >/dev/null 2>&1 || true
TOKEN=$(docker exec es01 bin/elasticsearch-service-tokens create elastic/kibana kibana | tail -n 1)
echo "KIBANA_SERVICE_TOKEN=$TOKEN" >> .env

export KIBANA_SERVICE_TOKEN="$TOKEN"
docker compose up -d

echo "Stack is running. Kibana service token stored in .env"

