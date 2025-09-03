#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../certs" && pwd)"
mkdir -p "$CERT_DIR"

# Generate Certificate Authority if not existing
if [[ ! -f "$CERT_DIR/ca.crt" ]]; then
  openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
    -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -subj "/CN=elk-stack-ca"
fi

generate_cert() {
  local name="$1"
  openssl req -newkey rsa:4096 -nodes \
    -keyout "$CERT_DIR/${name}.key" -out "$CERT_DIR/${name}.csr" \
    -subj "/CN=${name}" -addext "subjectAltName=DNS:${name}"
  openssl x509 -req -in "$CERT_DIR/${name}.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
    -out "$CERT_DIR/${name}.crt" -days 365 -sha256
  rm "$CERT_DIR/${name}.csr"
}

generate_cert es01
generate_cert kibana
generate_cert fleet-server

rm -f "$CERT_DIR/ca.srl"

echo "Certificates written to $CERT_DIR"
