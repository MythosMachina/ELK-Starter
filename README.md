# ELK Starter


Dieses Repository enthält ein Docker-Compose-Setup für einen einzelnen Elasticsearch-Knoten, Kibana und einen Fleet Server. Die Konfiguration basiert auf den Vorgaben aus `agents.md` und ist für Labor- bzw. Entwicklungsumgebungen gedacht.

## Quickstart

```bash
# Provisionierung (Docker & Kernel-Tuning)
sudo bash scripts/provision.sh

# Selbstsignierte Zertifikate erzeugen
bash scripts/generate-certs.sh

# Stack starten (Elasticsearch + Token + Kibana + Fleet)
bash scripts/start.sh
```

Danach stehen die Dienste verschlüsselt über Caddy zur Verfügung:

- Elasticsearch: https://es.local
- Kibana: https://kibana.local
- Fleet Server: https://fleet.local

Für eine erste Überprüfung:

```bash
curl -s --cacert certs/ca.crt -u elastic:$ELASTIC_PASSWORD https://es.local | jq .
```

Das `start.sh`-Skript entfernt vor dem Start automatisch einen eventuell
vorhandenen `KIBANA_SERVICE_TOKEN` aus der `.env`-Datei und erstellt einen
neuen Service-Token, um Probleme mit bereits existierenden Tokens zu vermeiden.

## Elastic Agent installieren

Das Repository enthält Skripte zur Installation eines Elastic Agents, der sich automatisch beim mitgelieferten Fleet Server anmeldet.

### Linux

```bash
ENROLLMENT_TOKEN=<token> bash scripts/install-agent-linux.sh
```

### Windows (PowerShell)

```powershell
.\scripts\install-agent-windows.ps1 -EnrollmentToken <token>
```

Beide Skripte verwenden standardmäßig die in `.env` definierte Version (`STACK_VERSION`). Für die aktuelle Version ist der Elastic Agent als Download verfügbar, sodass der aktuelle Agent genutzt werden kann.


## Verzeichnisstruktur

Alle persistenten Daten und Logs werden außerhalb der Container unter `/mnt/elastic_logs/` abgelegt:

```
/mnt/elastic_logs/
  elasticsearch/{config,data,logs}
  kibana/{config,logs}
  fleet-server/{agent,logs}
```

Weitere Hinweise zu Betrieb und Sicherheit finden sich in `agents.md`.
