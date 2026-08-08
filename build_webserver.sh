#!/bin/bash
set -euo pipefail

command -v docker >/dev/null || { echo "Docker wurde nicht gefunden. Bitte Docker Desktop installieren und starten." >&2; exit 1; }

docker build -t tt-site ./malicious-website
