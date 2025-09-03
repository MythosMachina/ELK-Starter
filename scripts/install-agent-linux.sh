#!/usr/bin/env bash
set -euo pipefail

# Root directory of the repository
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Elastic Agent version to install. Defaults to STACK_VERSION from .env or 8.16.3.
AGENT_VERSION="${AGENT_VERSION:-${STACK_VERSION:-8.16.3}}"
FLEET_URL="${FLEET_URL:-https://fleet.local}"

if [[ -z "${ENROLLMENT_TOKEN:-}" ]]; then
  echo "ENROLLMENT_TOKEN environment variable must be set" >&2
  exit 1
fi

TARBALL="elastic-agent-${AGENT_VERSION}-linux-x86_64.tar.gz"
DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/elastic-agent/${TARBALL}"

# Download and extract Elastic Agent
curl -fL -O "$DOWNLOAD_URL"
tar -xzf "$TARBALL"
cd "elastic-agent-${AGENT_VERSION}-linux-x86_64"

# Install and enroll the agent non-interactively
sudo ./elastic-agent install \
  --url "$FLEET_URL" \
  --enrollment-token "$ENROLLMENT_TOKEN" \
  --certificate-authorities "$REPO_ROOT/certs/ca.crt" \
  -b
