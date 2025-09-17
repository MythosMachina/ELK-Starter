#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CADDY_FILE="${ROOT_DIR}/configs/caddy/Caddyfile"
DEFAULT_DEPLOY_DIR="/opt/ELK"
PERSISTENT_BASE="/mnt/elastic_logs"

pause() {
  read -rp $'\nDrücke Enter, um zum Menü zurückzukehren...' _
}

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Für diese Option werden Root-Rechte benötigt." >&2
    echo "Bitte das Setup-Skript mit sudo oder als root ausführen." >&2
    return 1
  fi
  return 0
}

get_env_value() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 1
  fi
  python3 - "$ENV_FILE" "$key" <<'PYTHON'
import pathlib
import sys

env_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
value = None
for line in env_path.read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        continue
    current_key, current_value = stripped.split('=', 1)
    if current_key == key:
        value = current_value
if value is None:
    sys.exit(1)
print(value)
PYTHON
}

set_env_value() {
  local key="$1"
  local value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PYTHON'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
lines = []
found = False
if path.exists():
    for line in path.read_text().splitlines(keepends=True):
        if line.startswith(f"{key}="):
            lines.append(f"{key}={value}\n")
            found = True
        else:
            lines.append(line)
else:
    path.parent.mkdir(parents=True, exist_ok=True)
if not found:
    if lines and not lines[-1].endswith('\n'):
        lines[-1] = lines[-1] + '\n'
    lines.append(f"{key}={value}\n")
path.write_text(''.join(lines))
PYTHON
}

read_caddy_hosts() {
  if [[ ! -f "$CADDY_FILE" ]]; then
    return 1
  fi
  python3 - "$CADDY_FILE" <<'PYTHON'
import pathlib
import re
import sys

pattern = re.compile(r'(?m)^([^\s{]+)\s*{')
content = pathlib.Path(sys.argv[1]).read_text()
for host in pattern.findall(content):
    print(host)
PYTHON
}

update_caddy_hosts() {
  local old_es="$1"
  local new_es="$2"
  local old_kibana="$3"
  local new_kibana="$4"
  local old_fleet="$5"
  local new_fleet="$6"
  python3 - "$CADDY_FILE" \
    "$old_es" "$new_es" \
    "$old_kibana" "$new_kibana" \
    "$old_fleet" "$new_fleet" <<'PYTHON'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
args = sys.argv[2:]
pairs = list(zip(args[::2], args[1::2]))
content = path.read_text()
for old, new in pairs:
    pattern = re.compile(rf'(?m)^{re.escape(old)}\s*{')
    replacement = f"{new} " + "{"
    content = pattern.sub(replacement, content, count=1)
path.write_text(content)
PYTHON
}

setup_environments() {
  if [[ ! -f "$CADDY_FILE" ]]; then
    echo "Caddyfile wurde nicht gefunden (${CADDY_FILE})." >&2
    return 1
  fi

  mapfile -t hosts < <(read_caddy_hosts)
  local es_host="${hosts[0]:-es.local}"
  local kibana_host="${hosts[1]:-kibana.local}"
  local fleet_host="${hosts[2]:-fleet.local}"

  echo "Aktuelle FQDNs:"
  echo "  Elasticsearch: ${es_host}"
  echo "  Kibana:        ${kibana_host}"
  echo "  Fleet Server:  ${fleet_host}"
  echo

  read -rp "Neuer Elasticsearch-FQDN [${es_host}]: " new_es
  read -rp "Neuer Kibana-FQDN [${kibana_host}]: " new_kibana
  read -rp "Neuer Fleet-FQDN [${fleet_host}]: " new_fleet

  new_es=${new_es:-$es_host}
  new_kibana=${new_kibana:-$kibana_host}
  new_fleet=${new_fleet:-$fleet_host}

  if [[ "$new_es" != "$es_host" || "$new_kibana" != "$kibana_host" || "$new_fleet" != "$fleet_host" ]]; then
    update_caddy_hosts "$es_host" "$new_es" "$kibana_host" "$new_kibana" "$fleet_host" "$new_fleet"
    echo "Caddy-Konfiguration aktualisiert."
  else
    echo "FQDNs bleiben unverändert."
  fi

  local es_url="https://${new_es}"
  local kibana_url="https://${new_kibana}"
  local fleet_url="https://${new_fleet}"

  set_env_value "ELASTICSEARCH_PUBLIC_URL" "$es_url"
  set_env_value "KIBANA_PUBLIC_URL" "$kibana_url"
  set_env_value "FLEET_PUBLIC_URL" "$fleet_url"
  set_env_value "FLEET_URL" "$fleet_url"

  echo "Um die Änderungen in Zertifikaten zu übernehmen, bitte 'scripts/generate-certs.sh' erneut ausführen."
  echo "Umgebungsvariablen wurden aktualisiert."
  return 0
}

copy_repository() {
  local target_dir="$1"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git' --exclude '.github' "${ROOT_DIR}/" "${target_dir}/"
  else
    (cd "$ROOT_DIR" && tar --exclude='.git' --exclude='.github' -cf - .) | (cd "$target_dir" && tar -xf -)
  fi
}

setup_directories() {
  if ! ensure_root; then
    return 1
  fi

  read -rp "Zielverzeichnis für das Repository [${DEFAULT_DEPLOY_DIR}]: " deploy_dir
  deploy_dir=${deploy_dir:-$DEFAULT_DEPLOY_DIR}

  if [[ -z "$deploy_dir" ]]; then
    echo "Kein Zielverzeichnis angegeben." >&2
    return 1
  fi

  mkdir -p "$deploy_dir"
  copy_repository "$deploy_dir"
  echo "Repository nach ${deploy_dir} kopiert."

  mkdir -p \
    "${PERSISTENT_BASE}/elasticsearch/config" \
    "${PERSISTENT_BASE}/elasticsearch/data" \
    "${PERSISTENT_BASE}/elasticsearch/logs" \
    "${PERSISTENT_BASE}/kibana/config" \
    "${PERSISTENT_BASE}/kibana/logs" \
    "${PERSISTENT_BASE}/fleet-server/agent" \
    "${PERSISTENT_BASE}/fleet-server/logs"

  chown -R 1000:1000 "${PERSISTENT_BASE}/elasticsearch" "${PERSISTENT_BASE}/kibana"
  chown -R 0:0 "${PERSISTENT_BASE}/fleet-server" || true
  chmod -R 0775 "${PERSISTENT_BASE}"

  echo "Persistente Verzeichnisse unter ${PERSISTENT_BASE} vorbereitet."
  return 0
}

setup_dependencies() {
  if ! ensure_root; then
    return 1
  fi
  if [[ ! -x "${ROOT_DIR}/scripts/provision.sh" ]]; then
    echo "Das Provisioning-Skript wurde nicht gefunden." >&2
    return 1
  fi
  bash "${ROOT_DIR}/scripts/provision.sh"
  return 0
}

rollback() {
  if ! ensure_root; then
    return 1
  fi

  echo "Rollback-Optionen:"
  echo "  1) Nur Docker-Container stoppen/entfernen"
  echo "  2) Docker-Container und persistente Daten löschen"
  read -rp "Auswahl [1]: " choice
  choice=${choice:-1}

  read -rp "Pfad zum Docker-Projekt [${DEFAULT_DEPLOY_DIR}]: " project_dir
  project_dir=${project_dir:-$DEFAULT_DEPLOY_DIR}

  if [[ ! -f "${project_dir}/docker-compose.yml" ]]; then
    echo "Keine docker-compose.yml unter ${project_dir} gefunden." >&2
    return 1
  fi

  if docker compose version >/dev/null 2>&1; then
    (cd "$project_dir" && docker compose down --remove-orphans)
  elif command -v docker-compose >/dev/null 2>&1; then
    (cd "$project_dir" && docker-compose down --remove-orphans)
  else
    echo "Docker Compose ist nicht verfügbar." >&2
    return 1
  fi
  echo "Docker-Stack wurde gestoppt."

  if [[ "$choice" == "2" ]]; then
    read -rp "Persistente Daten unter ${PERSISTENT_BASE} wirklich löschen? (y/N): " confirm
    if [[ "${confirm,,}" == y* ]]; then
      rm -rf "${PERSISTENT_BASE}/elasticsearch" \
             "${PERSISTENT_BASE}/kibana" \
             "${PERSISTENT_BASE}/fleet-server"
      echo "Persistente Daten wurden entfernt."
    else
      echo "Löschen der Daten abgebrochen."
    fi
  fi
  return 0
}

display_urls_and_secrets() {
  if [[ ! -f "$CADDY_FILE" ]]; then
    echo "Caddyfile wurde nicht gefunden." >&2
    return 1
  fi

  mapfile -t hosts < <(read_caddy_hosts)
  local es_host="${hosts[0]:-es.local}"
  local kibana_host="${hosts[1]:-kibana.local}"
  local fleet_host="${hosts[2]:-fleet.local}"

  local es_url="https://${es_host}"
  local kibana_url="https://${kibana_host}"
  local fleet_url="https://${fleet_host}"

  echo "Verfügbare URLs:"
  echo "  Elasticsearch: ${es_url}"
  echo "  Kibana:        ${kibana_url}"
  echo "  Fleet Server:  ${fleet_url}"
  echo

  local elastic_password=""
  local kibana_token=""
  local fleet_url_env=""

  if elastic_password=$(get_env_value "ELASTIC_PASSWORD" 2>/dev/null); then
    echo "ELASTIC_PASSWORD=${elastic_password}"
  else
    echo "ELASTIC_PASSWORD ist nicht gesetzt."
  fi

  if kibana_token=$(get_env_value "KIBANA_SERVICE_TOKEN" 2>/dev/null); then
    echo "KIBANA_SERVICE_TOKEN=${kibana_token}"
  else
    echo "KIBANA_SERVICE_TOKEN ist noch nicht vorhanden."
  fi

  if fleet_url_env=$(get_env_value "FLEET_URL" 2>/dev/null); then
    echo "Fleet Enrollment URL: ${fleet_url_env}"
  else
    echo "Fleet Enrollment URL: ${fleet_url}"
  fi

  echo "CA-Zertifikat: ${ROOT_DIR}/certs/ca.crt"
  return 0
}

main_menu() {
  while true; do
    cat <<'MENU'
=============================
 ELK Setup Menü
=============================
1) Setup Environments (FQDN/Domain)
2) Setup Directories (/opt/ELK + Persistenz)
3) Setup Dependencies (Docker & Voraussetzungen)
4) Rollback / Teil-Rollback
5) Display URLs & Secrets
6) Exit
MENU

    read -rp "Bitte eine Option wählen: " selection
    case "$selection" in
      1)
        if ! setup_environments; then
          echo "Fehler beim Aktualisieren der Umgebungseinstellungen." >&2
        fi
        pause
        ;;
      2)
        if ! setup_directories; then
          echo "Fehler beim Anlegen der Verzeichnisse." >&2
        fi
        pause
        ;;
      3)
        if ! setup_dependencies; then
          echo "Fehler beim Installieren der Abhängigkeiten." >&2
        fi
        pause
        ;;
      4)
        if ! rollback; then
          echo "Rollback fehlgeschlagen." >&2
        fi
        pause
        ;;
      5)
        if ! display_urls_and_secrets; then
          echo "Informationen konnten nicht angezeigt werden." >&2
        fi
        pause
        ;;
      6)
        echo "Setup beendet."
        break
        ;;
      *)
        echo "Ungültige Auswahl."
        ;;
    esac
  done
}

main_menu
