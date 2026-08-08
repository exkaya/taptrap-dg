$ErrorActionPreference = "Stop"

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    throw "openssl wurde nicht gefunden. Es wird z.B. mit 'Git for Windows' oder 'choco install openssl' mitgeliefert."
}

# Ablage immer im certs-Ordner, unabhaengig davon von wo das Skript aufgerufen wird.
Set-Location $PSScriptRoot

Write-Host "Erstelle Root CA's private key"
openssl genrsa -out rootCA.key 4096

Write-Host "Erstelle Root CA's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
@'
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = DE
O = Local Development
CN = HSNR TapTrap Local Development Root CA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
'@ | Set-Content -Encoding ascii rootCA.cnf

Write-Host "Erstelle Root CA Zertifikat mithilfe des private key und der Konfigurationsdatei"
openssl req -x509 -new -key rootCA.key -sha256 -days 3650 -out rootCA.crt -config rootCA.cnf

Write-Host "Erstelle Server's private key"
openssl genrsa -out server.key 2048

Write-Host "Erstelle Server's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
@'
[req]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C = DE
O = Local Development
CN = localhost

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.0.2.2
'@ | Set-Content -Encoding ascii server.cnf

Write-Host "Erstelle Certificate Signing Request"
openssl req -new -key server.key -out server.csr -config server.cnf

Write-Host "Signiere Server's Certificate Signing Request mit dem Root CA"
openssl x509 -req -in server.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile server.cnf -extensions v3_req

Write-Host "Verifiziere die Zertifizierungskette (sollte 'server.crt: OK' ausgeben)"
openssl verify -CAfile rootCA.crt server.crt
