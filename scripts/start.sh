#!/usr/bin/env bash

set -euo pipefail

# Always execute from repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Load environment variables
source .env

echo "[1/3] Start Elasticsearch"
docker compose up -d es01

echo "[2/3] Waiting for Elasticsearch to respond"
until curl -s -u elastic:"$ELASTIC_PASSWORD" http://localhost:9200 >/dev/null 2>&1; do
  sleep 2
done

echo "[3/3] Create Kibana service account token"
TOKEN=$(docker exec es01 bin/elasticsearch-service-tokens create elastic/kibana kibana | tail -n 1)

if grep -q '^KIBANA_SERVICE_TOKEN=' .env; then
  sed -i "s/^KIBANA_SERVICE_TOKEN=.*/KIBANA_SERVICE_TOKEN=$TOKEN/" .env
else
  echo "KIBANA_SERVICE_TOKEN=$TOKEN" >> .env
fi

export KIBANA_SERVICE_TOKEN="$TOKEN"
docker compose up -d

echo "Stack is running. Kibana service token stored in .env"

