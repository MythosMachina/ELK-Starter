# AGENTS.md — ELK + Fleet Server (Docker Stack)

## Ziel

Ein reproduzierbares, „einmal starten & läuft“-Setup für:

* **Elasticsearch (Single Node)**
* **Kibana**
* **Fleet Server** (Elastic Agent im Fleet-Server-Modus)
  mit:
* vordefiniertem **Docker Compose** + **Bridge-Network** (`elk-net`)
* **automatischer Provisionierung** (Docker, Compose-Plugin, Kernel-Tuning)
* **externe Persistenz** von **Config** und **Logs** unter `/mnt/elastic_logs/<container>`
* **exponierten Ports**: `9200` (ES), `5601` (Kibana), `8220` (Fleet Server)

> Hinweise
> • Das Setup ist bewusst „lab/dev-freundlich“ (HTTP ohne TLS). Für Produktion unbedingt TLS & Härtung aktivieren.
> • Fleet/Agent-Variablen und Bootstrapping entsprechen den aktuellen Elastic-Dokus zu Agent/Fleet-Environment-Variablen. ([Elastic][1])

---

## Topologie & Ports

```
[Host]  ─ docker ─┬─ es01 (9200,9300)
                  ├─ kibana (5601)
                  └─ fleet-server (8220)
        └ network: elk-net (bridge)
```

Exposed nach außen:

* `9200:9200` (Elasticsearch HTTP API)
* `5601:5601` (Kibana UI)
* `8220:8220` (Fleet Server für Agent-Enrollments)

---

## Verzeichnislayout auf dem Host

Alle wichtigen Daten/Logs extern unter `/mnt/elastic_logs`:

```
/mnt/elastic_logs/
  elasticsearch/
    config/         # bereitgestellte elasticsearch.yml (RO ins Container-Config gemountet)
    data/           # ES-Daten
    logs/           # ES-File-Logs
  kibana/
    config/         # kibana.yml (RO gemountet)
    logs/           # Kibana-File-Logs
  fleet-server/
    agent/          # Persistenz für Elastic Agent/Fleet Server
    logs/           # Agent/Fleet-Logs (optional)
```

---

## Quickstart

```bash
# 1) Repo-Struktur anlegen
mkdir -p elk-stack && cd elk-stack

# 2) Dateien aus diesem Dokument anlegen (siehe „Dateien“ unten)

# 3) Provisionieren (Docker + Kernel-Tuning + Verzeichnisse)
sudo bash scripts/provision.sh

# 4) Stack starten
docker compose up -d

# 5) Smoke-Tests
curl -s -u elastic:$ELASTIC_PASSWORD http://localhost:9200 | jq .
xdg-open http://localhost:5601  # (Linux Desktop) – sonst Browser aufrufen
```

> Wichtiger Kernel-Tweak: `vm.max_map_count` muss **>= 262144** sein (Provisioning-Script setzt das). ([Elastic][2])

---

## Dateien

> Lege die folgenden Dateien exakt so in deinem `elk-stack/` Ordner an.

### 1) `.env`

```dotenv
# Elastic Version zentral steuern (8.16.x ist aktuell verbreitet; bei Bedarf anpassen)
STACK_VERSION=8.16.3

# Superuser-Passwort für Elasticsearch (auch für Kibana/Fleet in diesem Setup)
ELASTIC_PASSWORD=ChangeMe_please_!2025

# JVM & Ressourcen
ES_JAVA_OPTS=-Xms1g -Xmx1g
```

---

### 2) `docker-compose.yml`

```yaml
name: elk-stack

networks:
  elk-net:
    name: elk-net
    driver: bridge

services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}
    container_name: es01
    restart: unless-stopped
    environment:
      - node.name=es01
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
      # Security an, HTTP ohne TLS (dev)
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      # Logs in Datei (wird gemountet)
      - path.logs=/usr/share/elasticsearch/logs
      # Benutzerpasswort (Superuser)
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    ports:
      - "9200:9200"
      - "9300:9300"
    volumes:
      - /mnt/elastic_logs/elasticsearch/data:/usr/share/elasticsearch/data
      - /mnt/elastic_logs/elasticsearch/logs:/usr/share/elasticsearch/logs
      - ./configs/elasticsearch/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
    networks:
      - elk-net

  kibana:
    image: docker.elastic.co/kibana/kibana:${STACK_VERSION}
    container_name: kibana
    restart: unless-stopped
    depends_on:
      - es01
    environment:
      # Fürs Bootstrapping verwenden wir den elastic-User
      - ELASTICSEARCH_HOSTS=http://es01:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD}
      # Optional: öffentlich erreichbare Basis-URL (für Links)
      - SERVER_PUBLICBASEURL=${KIBANA_PUBLIC_URL:-http://localhost:5601}
    ports:
      - "5601:5601"
    volumes:
      - ./configs/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
      - /mnt/elastic_logs/kibana/logs:/usr/share/kibana/logs
    networks:
      - elk-net

  fleet-server:
    image: docker.elastic.co/beats/elastic-agent:${STACK_VERSION}
    container_name: fleet-server
    restart: unless-stopped
    depends_on:
      - es01
      - kibana
    environment:
      # Fleet Server aktivieren & an ES/Kibana koppeln (HTTP, ohne TLS)
      - FLEET_SERVER_ENABLE=1
      - FLEET_SERVER_ELASTICSEARCH_HOST=http://es01:9200
      - FLEET_SERVER_INSECURE_HTTP=true
      # (Ab neueren Releases erledigt Kibana die Fleet-Initialisierung selbst.
      #  KIBANA_FLEET_SETUP kann i.d.R. entfallen.)
      - KIBANA_HOST=http://kibana:5601
      - KIBANA_USERNAME=elastic
      - KIBANA_PASSWORD=${ELASTIC_PASSWORD}
      # Gemeinsame ES-Creds (werden auch vom Agent genutzt)
      - ELASTICSEARCH_HOST=http://es01:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD}
      - LOG_LEVEL=info
    ports:
      - "8220:8220"
    volumes:
      # Persistente Agent-/Fleet-Server-Daten & -Logs
      # Wichtig: Nur das Datenverzeichnis mounten – ein Bind auf /usr/share/elastic-agent
      # würde das Agent-Binary überschreiben und der Container könnte nicht starten.
      - /mnt/elastic_logs/fleet-server/agent:/usr/share/elastic-agent/data
      - /mnt/elastic_logs/fleet-server/logs:/var/log/elastic-agent
    networks:
      - elk-net
```

**Warum diese Variablen?**
Die hier verwendeten Fleet/Agent-Variablen (u. a. `FLEET_SERVER_ENABLE`, `FLEET_SERVER_ELASTICSEARCH_HOST`, `KIBANA_HOST`, `ELASTICSEARCH_HOST`, `…_USERNAME`, `…_PASSWORD`, `FLEET_SERVER_INSECURE_HTTP`) sind in den offiziellen Elastic-Referenzen dokumentiert. ([Elastic][1])

---

### 3) `configs/elasticsearch/elasticsearch.yml`

```yaml
cluster.name: docker-cluster
node.name: es01
discovery.type: single-node

# Logging-Tuning (optional)
logger.level: info

# Achtung: Dieses Setup nutzt HTTP ohne TLS (nur Dev!)
xpack.security.enabled: true
xpack.security.http.ssl:
  enabled: false
xpack.security.transport.ssl:
  enabled: false

path:
  data: /usr/share/elasticsearch/data
  logs: /usr/share/elasticsearch/logs

# Für Docker-Umgebungen üblich:
network.host: 0.0.0.0
```

---

### 4) `configs/kibana/kibana.yml`

```yaml
server.host: 0.0.0.0
server.publicBaseUrl: ${SERVER_PUBLICBASEURL:http://localhost:5601}

# Verbindung zu ES (hier via Superuser – für Produktion separat absichern!)
elasticsearch.hosts: ["http://es01:9200"]
elasticsearch.username: ${ELASTICSEARCH_USERNAME:elastic}
elasticsearch.password: ${ELASTIC_PASSWORD}

# File-Logging aktivieren (statt nur stdout)
logging:
  appenders:
    file:
      type: file
      fileName: /usr/share/kibana/logs/kibana.log
      layout:
        type: json
  root:
    level: info
    appenders: [file]

```

---

### 5) `scripts/provision.sh`

```bash
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
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
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
```

> Warum `vm.max_map_count`? Elasticsearch fordert mindestens **262144** (Host-seitig) – ohne den Wert startet ES fehlerhaft. ([Elastic][2])

---

### 6) (optional) systemd-Unit `systemd/elk-stack.service`

```ini
[Unit]
Description=ELK + Fleet Server (docker compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/elk-stack
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

> Kopiere dein Projekt nach `/opt/elk-stack` und aktiviere:
> `sudo cp systemd/elk-stack.service /etc/systemd/system/`
> `sudo systemctl daemon-reload && sudo systemctl enable --now elk-stack`

---

## Betrieb

### Start/Stop/Status

```bash
docker compose up -d
docker compose ps
docker compose logs -f es01
docker compose logs -f kibana
docker compose logs -f fleet-server
docker compose down
```

### Smoke-Tests

```bash
# ES erreichbar?
curl -s -u elastic:$ELASTIC_PASSWORD http://localhost:9200 | jq .

# Kibana im Browser: http://localhost:5601  (Login: elastic / $ELASTIC_PASSWORD)

# Fleet Server Port offen?
nc -zv localhost 8220
```

### Logs & Konfiguration am Host

* ES-Logs: `/mnt/elastic_logs/elasticsearch/logs/`
* ES-Daten: `/mnt/elastic_logs/elasticsearch/data/`
* Kibana-Logs: `/mnt/elastic_logs/kibana/logs/kibana.log`
* Fleet-Server/Agent-Daten: `/mnt/elastic_logs/fleet-server/agent/`
* Fleet-Logs (optional): `/mnt/elastic_logs/fleet-server/logs/`

---

## Sicherheit & Produktion

* **TLS aktivieren** (HTTPS für ES/Kibana/Fleet): In prod **nicht** `FLEET_SERVER_INSECURE_HTTP=true` nutzen; Zertifikate/CA in Agent-Vars (`…_CA`) hinterlegen. Referenzvariablen siehe Elastic-Doku. ([Elastic][1])
* **Separate Service-User** in Kibana/ES nutzen (nicht `elastic`).
* **Passwörter/Secrets** via Docker Secrets/Env-Files.
* **Ressourcen** (RAM/CPU) je nach Datenlast erhöhen.
* **Backup**: Snapshots (ES) + persistente Volumes sichern.

---

## Troubleshooting (Kurz)

* **ES startet nicht, „vm.max\_map\_count zu niedrig“** → Provisioning erneut laufen lassen oder `sudo sysctl -w vm.max_map_count=262144`. ([Elastic][2])
* **Kibana „unavailable“** → Prüfe `docker compose logs kibana` & ES-Status (`curl /_cluster/health`).
* **Fleet Server lauscht nicht extern** → Stelle sicher, dass Compose Port `8220:8220` mapped ist und keine FW blockt; in unserem Setup ist Binding 0.0.0.0 via Container-Defaults aktiv, HTTP unsicher ist explizit freigeschaltet (`FLEET_SERVER_INSECURE_HTTP=true`). Variablen-Referenzen: ([Elastic][1])
* **Enrollments von Agents** → Agents gegen `http://<HOST-IP>:8220` anmelden (dev, ohne TLS mit `--insecure`). Fleet-URL findest du in Kibana → Fleet → Einstellungen.

---

## Warum dieses Fleet-Bootstrapping?

* Wir nutzen den **Elastic Agent im Container** mit `FLEET_SERVER_ENABLE=1` plus den **Common Vars** (`ELASTICSEARCH_*`, `KIBANA_*`). Das ermöglicht, Fleet Server **ohne separate Pre-Token-Skripte** hochzuziehen – ideal für Compose-Automatisierung. Details & Var-Referenz: ([Elastic][1])

---

## Anhang: Makefile (optional)

```make
up:
\tdocker compose up -d

down:
\tdocker compose down

logs:
\tdocker compose logs -f

ps:
\tdocker compose ps

rebuild:
\tdocker compose pull && docker compose up -d --remove-orphans
```



[1]: https://www.elastic.co/docs/reference/fleet/agent-environment-variables "Elastic Agent environment variables | Elastic Docs"
[2]: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-prod?utm_source=chatgpt.com "Using the Docker images in production"
