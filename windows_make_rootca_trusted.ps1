#Requires -RunAsAdministrator
# Dieses Skript muss in einer PowerShell ausgefuehrt werden, die "Als Administrator ausfuehren" gestartet wurde,
# da das Root-Zertifikat sonst nicht im Windows-Zertifikatspeicher abgelegt werden darf.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rootCA = "certs\rootCA.crt"

if (-not (Test-Path $rootCA)) {
    throw "certs\rootCA.crt wurde nicht gefunden. Bitte zuerst certs\build_cert_chain.ps1 ausfuehren."
}

certutil -addstore -f "Root" $rootCA
if ($LASTEXITCODE -ne 0) { throw "certutil ist fehlgeschlagen." }

Write-Host "Root-Zertifikat wurde als vertrauenswuerdig markiert."

# Zum spaeteren Entfernen des Zertifikats aus dem Windows-Zertifikatspeicher:
# certutil -delstore "Root" "HSNR TapTrap Local Development Root CA"
