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
  url="${url%%/*}"
  echo "${url%%:*}"
}

prompt_overwrite() {
  shopt -s nullglob
  local existing=("${CERT_DIR}"/*.crt "${CERT_DIR}"/*.key)
  shopt -u nullglob
  if (( ${#existing[@]} == 0 )); then
    return 0
  fi

  echo "Es existieren bereits Zertifikate im Verzeichnis ${CERT_DIR}."
  read -rp "Sollen sie neu erstellt werden? [y/N]: " answer
  case "${answer}" in
    [yY][eE][sS]|[yY])
      rm -f "${CERT_DIR}"/*.crt "${CERT_DIR}"/*.key "${CERT_DIR}"/*.srl
      ;;
    *)
      echo "Abgebrochen – vorhandene Zertifikate bleiben erhalten."
      exit 0
      ;;
  esac
}

build_san() {
  declare -A seen=()
  for host in "$@"; do
    [[ -z "${host}" ]] && continue
    seen["${host}"]=1
  done

  local sorted_hosts=()
  if ((${#seen[@]} > 0)); then
    mapfile -t sorted_hosts < <(printf '%s\n' "${!seen[@]}" | sort)
  fi

  local entries=()
  for host in "${sorted_hosts[@]}"; do
    entries+=("DNS:${host}")
  done

  IFS=","; echo "${entries[*]}"; unset IFS
}

prompt_overwrite

ELASTICSEARCH_PUBLIC_HOST="${ELASTICSEARCH_PUBLIC_URL:-https://es.local}"
ELASTICSEARCH_PUBLIC_HOST="$(extract_host "$ELASTICSEARCH_PUBLIC_HOST")"

KIBANA_PUBLIC_HOST="${KIBANA_PUBLIC_URL:-https://kibana.local}"
KIBANA_PUBLIC_HOST="$(extract_host "$KIBANA_PUBLIC_HOST")"

FLEET_PUBLIC_HOST="${FLEET_PUBLIC_URL:-https://fleet.local}"
FLEET_PUBLIC_HOST="$(extract_host "$FLEET_PUBLIC_HOST")"

FLEET_INTERNAL_HOST=""
if [[ -n "${FLEET_URL:-}" ]]; then
  FLEET_INTERNAL_HOST="$(extract_host "$FLEET_URL")"
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
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial -copy_extensions copy \
    -out "$CERT_DIR/${name}.crt" -days 365 -sha256
  rm "$CERT_DIR/${name}.csr"
}

# Include localhost as an additional Subject Alternative Name for Elasticsearch
generate_cert es01 "$(build_san es01 localhost "${ELASTICSEARCH_PUBLIC_HOST}")"
generate_cert kibana "$(build_san kibana localhost "${KIBANA_PUBLIC_HOST}")"
generate_cert fleet-server "$(build_san fleet-server localhost "${FLEET_PUBLIC_HOST}" "${FLEET_INTERNAL_HOST}")"
generate_cert caddy "$(build_san caddy localhost "${ELASTICSEARCH_PUBLIC_HOST}" "${KIBANA_PUBLIC_HOST}" "${FLEET_PUBLIC_HOST}" es01 kibana fleet-server)"

rm -f "$CERT_DIR/ca.srl"

echo "Certificates written to $CERT_DIR"
