$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker wurde nicht gefunden. Bitte Docker Desktop installieren und starten."
}

$cert = Join-Path (Get-Location) "certs\server.crt"
$key  = Join-Path (Get-Location) "certs\server.key"

if (-not (Test-Path $cert) -or -not (Test-Path $key)) {
    throw "Zertifikate wurden nicht gefunden. Bitte zuerst certs\build_cert_chain.ps1 ausfuehren."
}

# Docker erwartet Pfade mit Schraegstrichen, auch unter Windows.
$cert = $cert -replace '\\', '/'
$key  = $key -replace '\\', '/'

docker run --rm `
  -p 5002:5002 `
  -v "${cert}:/etc/nginx/certs/server.crt:ro" `
  -v "${key}:/etc/nginx/certs/server.key:ro" `
  tt-site
