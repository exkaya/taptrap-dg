$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker wurde nicht gefunden. Bitte Docker Desktop installieren und starten."
}

docker build -t tt-site ./malicious-website
if ($LASTEXITCODE -ne 0) { throw "docker build ist fehlgeschlagen." }
