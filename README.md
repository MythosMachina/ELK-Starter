# ELK Starter 🚀

> Moderner Entwicklungs-Stack für Elasticsearch, Kibana & Fleet Server – automatisiert per Docker Compose.

![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Elastic Stack](https://img.shields.io/badge/Elastic%20Stack-8.x-005571?logo=elastic&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

## Inhaltsverzeichnis

1. [Überblick](#überblick)
2. [Highlights](#highlights)
3. [Projektstruktur](#projektstruktur)
4. [Voraussetzungen](#voraussetzungen)
5. [Setup – Schritt für Schritt](#setup--schritt-für-schritt)
6. [Nach dem Start](#nach-dem-start)
7. [Elastic Agent Onboarding](#elastic-agent-onboarding)
8. [Betrieb & Wartung](#betrieb--wartung)
9. [Troubleshooting & Ressourcen](#troubleshooting--ressourcen)

---

## Überblick

Dieses Repository liefert ein vorkonfiguriertes Docker-Compose-Stack für einen einzelnen Elasticsearch-Knoten, Kibana sowie einen Fleet Server. Es richtet sich an Lab- und Entwicklungsumgebungen und greift auf die Vorgaben in [`agents.md`](agents.md) zurück, um ein reproduzierbares Setup zu bieten – inklusive Provisionierungsskripten, TLS per Caddy-Proxy und persistenter Ablage der Daten auf dem Host.

## Highlights

| ✅ Feature | Beschreibung |
| --- | --- |
| **One-Command-Provisioning** | `scripts/provision.sh` kümmert sich um Docker, Kernel-Tuning (`vm.max_map_count`) und Verzeichnisstruktur. |
| **Automatisierte Zertifikate** | `scripts/generate-certs.sh` erzeugt eine lokale CA, übernimmt Domains aus `.env` sowie Container-Hostnamen in die SAN-Liste und warnt vor Überschreibungen bestehender Zertifikate. |
| **Sicherer Fleet-Start** | `scripts/start.sh` startet Elasticsearch & Caddy, erstellt ein frisches Kibana-Service-Token und bringt Fleet/Kibana danach online. |
| **Interactive Setup** | `scripts/setup.sh` vereint alle Schritte in einem Menü mit Rollback-, Secrets- und Directory-Optionen. |
| **Fleet-Agent-Installer** | Skripte für Linux & Windows enrollen den Elastic Agent direkt gegen den mitgelieferten Fleet Server. |

## Projektstruktur

| Pfad | Inhalt |
| --- | --- |
| `docker-compose.yml` | Definition des Stacks (Elasticsearch, Kibana, Fleet Server, Caddy). |
| `.env` | Zentrale Variablen wie `STACK_VERSION`, Passwörter und öffentliche URLs. |
| `scripts/` | Provisionierung, Zertifikatsgenerierung, Start/Setup sowie Agent-Installer. |
| `configs/` | Vorkonfigurierte `elasticsearch.yml`, `kibana.yml` und Fleet-Konfigurationen. |
| `certs/` | Platz für selbstsignierte CA, Zertifikate und Schlüssel (generiert durch Skript). |
| `systemd/` | Optionale Unit, um den Stack als Service zu betreiben. |
| `/mnt/elastic_logs/` (Host) | Persistente Daten & Logs für Elasticsearch, Kibana und Fleet Server. |

## Voraussetzungen

- Linux-Host mit Docker Engine ≥ 24 und Docker Compose Plugin.
- `sudo`-Rechte für Provisionierung und Kernel-Anpassungen.
- (Optional) `jq` für die Smoke-Tests.
- DNS- oder Hosts-Einträge, damit `es.local`, `kibana.local` und `fleet.local` auf den Host zeigen.

> ℹ️ Passe die Werte in `.env` vor dem Start an (Passwort, URLs, Heap-Größe usw.).

## Setup – Schritt für Schritt

```mermaid
graph LR
  A[Repo klonen] --> B[.env anpassen]
  B --> C[Provisionieren]
  C --> D[Zertifikate erzeugen]
  D --> E[Stack starten]
  E --> F[Smoke-Test]
```

1. **Repository vorbereiten**
   ```bash
   git clone https://github.com/<dein-user>/ELK-Starter.git
   cd ELK-Starter
   cp .env .env.local && edit .env.local  # optionaler Backup/Anpassung
   ```
   > Tipp: `scripts/setup.sh` führt dich interaktiv durch Domain- und Pfad-Anpassungen.

2. **Provisionierung ausführen** – richtet Docker, Kernel-Werte und Ordnerstruktur ein.
   ```bash
   sudo bash scripts/provision.sh
   ```

3. **TLS-Zertifikate generieren** – erstellt eine lokale CA und Service-Zertifikate im Ordner `certs/`.
   ```bash
   bash scripts/generate-certs.sh
   ```
   - Bezieht die öffentlichen URLs aus `.env` sowie die Container-Namen (`es01`, `kibana`, `fleet-server`, `caddy`) in jedes Zertifikat mit ein.
   - Erkennt vorhandene Zertifikate und fragt nach, bevor Schlüssel oder CA ersetzt werden.

4. **Stack starten** – Elasticsearch, Kibana, Fleet Server und Caddy werden hochgefahren.
   ```bash
   bash scripts/start.sh
   ```

   - Das Skript räumt `KIBANA_SERVICE_TOKEN` in `.env` auf und schreibt ein frisches Token zurück.
   - Fleet Server und Kibana starten erst, nachdem Elasticsearch gesund ist.

5. **Optional: Interaktiver Modus**
   ```bash
   bash scripts/setup.sh
   ```
   Menü-Optionen decken Umgebungsvariablen, Persistenzpfade, Abhängigkeiten, Rollback sowie eine Übersicht über URLs und Secrets ab.

## Nach dem Start

- **Zugänge**
  - Elasticsearch: `https://es.local`
  - Kibana: `https://kibana.local`
  - Fleet Server: `https://fleet.local`

- **Smoke-Test**
  ```bash
  curl -s --cacert certs/ca.crt -u elastic:$ELASTIC_PASSWORD https://es.local | jq .
  ```

- **Kibana Login** mit Benutzer `elastic` und dem Passwort aus `.env`.

- **Service Token prüfen**: `grep KIBANA_SERVICE_TOKEN .env`.

## Elastic Agent Onboarding

Verwende die mitgelieferten Skripte, um Agents automatisiert im Fleet Server zu registrieren. Setze dazu `ENROLLMENT_TOKEN` auf das Token aus Kibana → Fleet → Enrollment-Tokens.

### Linux

```bash
ENROLLMENT_TOKEN=<token> bash scripts/install-agent-linux.sh
```

### Windows (PowerShell)

```powershell
./scripts/install-agent-windows.ps1 -EnrollmentToken <token>
```

Beide Skripte nutzen standardmäßig die `STACK_VERSION` aus `.env` und laden den passenden Agent direkt von Elastic.

## Betrieb & Wartung

| Aufgabe | Befehl(e) |
| --- | --- |
| **Status prüfen** | `docker compose ps` |
| **Logs streamen** | `docker compose logs -f es01`, `docker compose logs -f kibana`, `docker compose logs -f fleet-server` |
| **Stack stoppen** | `docker compose down` |
| **Stack neu starten** | `bash scripts/start.sh` oder `docker compose up -d` |
| **Images aktualisieren** | `docker compose pull` gefolgt von `docker compose up -d --remove-orphans` |
| **Persistente Daten** | Liegen unter `/mnt/elastic_logs/<dienst>/` (Config, Daten, Logs). |
| **Systemd-Betrieb** | `sudo cp systemd/elk-stack.service /etc/systemd/system/` → `sudo systemctl enable --now elk-stack` |

> 📦 **Backup-Empfehlung:** Elasticsearch-Snapshots (API) plus Sicherung der Verzeichnisse unter `/mnt/elastic_logs/`.

## Troubleshooting & Ressourcen

- Details zur Topologie, Kernel-Parametern und Sicherheitsempfehlungen findest du in [`agents.md`](agents.md).
- Typische Stolperfallen:
  - `vm.max_map_count` zu niedrig → Provisionierung erneut ausführen oder `sudo sysctl -w vm.max_map_count=262144` setzen.
  - Kibana nicht erreichbar → `docker compose logs kibana` prüfen und sicherstellen, dass Elasticsearch grün ist (`curl /_cluster/health`).
  - Fleet Agent kann sich nicht registrieren → CA (`certs/ca.crt`) und `FLEET_PUBLIC_URL`/`FLEET_URL` in `.env` überprüfen.
- Offizielle Elastic-Dokumentation: [Elastic Agent Environments](https://www.elastic.co/docs/reference/fleet/agent-environment-variables) & [Elasticsearch Docker Guide](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-prod).

Viel Erfolg beim Aufbau deiner Observability-Umgebung! 💡
