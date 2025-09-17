#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CERT_DIR="${ROOT_DIR}/certs"
mkdir -p "$CERT_DIR"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

extract_host() {
  local url="$1"
  url="${url#http://}"
  url="${url#https://}"
  echo "${url%%/*}"
}

if [[ -n "${ELASTICSEARCH_PUBLIC_URL:-}" ]]; then
  ELASTICSEARCH_PUBLIC_HOST="$(extract_host "$ELASTICSEARCH_PUBLIC_URL")"
else
  ELASTICSEARCH_PUBLIC_HOST="es.local"
fi

if [[ -n "${KIBANA_PUBLIC_URL:-}" ]]; then
  KIBANA_PUBLIC_HOST="$(extract_host "$KIBANA_PUBLIC_URL")"
else
  KIBANA_PUBLIC_HOST="kibana.local"
fi

if [[ -n "${FLEET_PUBLIC_URL:-}" ]]; then
  FLEET_PUBLIC_HOST="$(extract_host "$FLEET_PUBLIC_URL")"
else
  FLEET_PUBLIC_HOST="fleet.local"
fi

# Generate Certificate Authority if not existing
if [[ ! -f "$CERT_DIR/ca.crt" ]]; then
  openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
    -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -subj "/CN=elk-stack-ca"
fi

generate_cert() {
  local name="$1"
  local san="${2:-DNS:${name}}"
  openssl req -newkey rsa:4096 -nodes \
    -keyout "$CERT_DIR/${name}.key" -out "$CERT_DIR/${name}.csr" \
    -subj "/CN=${name}" -addext "subjectAltName=${san}"
  openssl x509 -req -in "$CERT_DIR/${name}.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
    -out "$CERT_DIR/${name}.crt" -days 365 -sha256
  rm "$CERT_DIR/${name}.csr"
}

# Include localhost as an additional Subject Alternative Name for Elasticsearch
generate_cert es01 "DNS:es01,DNS:localhost"
generate_cert kibana
generate_cert fleet-server
generate_cert caddy "DNS:${ELASTICSEARCH_PUBLIC_HOST},DNS:${KIBANA_PUBLIC_HOST},DNS:${FLEET_PUBLIC_HOST}"

rm -f "$CERT_DIR/ca.srl"

echo "Certificates written to $CERT_DIR"
