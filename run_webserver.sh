#!/bin/bash
set -euo pipefail

command -v docker >/dev/null || { echo "Docker wurde nicht gefunden. Bitte Docker Desktop installieren und starten." >&2; exit 1; }

if [ ! -f "certs/server.crt" ] || [ ! -f "certs/server.key" ]; then
  echo "Zertifikate wurden nicht gefunden. Bitte zuerst certs/build_cert_chain.sh ausfuehren." >&2
  exit 1
fi

docker run --rm \
  -p 5002:5002 \
  -v "$PWD/certs/server.crt:/etc/nginx/certs/server.crt:ro" \
  -v "$PWD/certs/server.key:/etc/nginx/certs/server.key:ro" \
  tt-site
