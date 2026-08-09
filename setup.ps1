<#
Interactive setup helper for Windows. Run without arguments for a menu,
or pass a step name directly, e.g. .\setup.ps1 certs
#>
param(
    [Parameter(Position = 0)]
    [string]$Step
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$CertDir = "certs"

function Test-Cmd {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' wurde nicht gefunden. $Hint"
    }
}

function Invoke-Native {
    $exe = $args[0]
    $rest = $args[1..($args.Count - 1)]
    & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        throw "'$exe' ist fehlgeschlagen (Exit-Code $LASTEXITCODE)."
    }
}

function Step-Certs {
    Test-Cmd openssl "Bitte OpenSSL installieren (z.B. ueber 'Git for Windows')."
    New-Item -ItemType Directory -Force -Path $CertDir | Out-Null
    Push-Location $CertDir
    try {
        Write-Host "Erstelle Root CA's private key"
        Invoke-Native openssl genrsa -out rootCA.key 4096

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
        Invoke-Native openssl req -x509 -new -key rootCA.key -sha256 -days 3650 -out rootCA.crt -config rootCA.cnf

        Write-Host "Erstelle Server's private key"
        Invoke-Native openssl genrsa -out server.key 2048

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
        Invoke-Native openssl req -new -key server.key -out server.csr -config server.cnf

        Write-Host "Signiere Server's Certificate Signing Request mit dem Root CA"
        Invoke-Native openssl x509 -req -in server.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile server.cnf -extensions v3_req

        Write-Host "Verifiziere die Zertifizierungskette (sollte 'server.crt: OK' ausgeben)"
        Invoke-Native openssl verify -CAfile rootCA.crt server.crt
    }
    finally {
        Pop-Location
    }
}

function Step-Trust {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Dieser Schritt benoetigt eine PowerShell, die 'Als Administrator ausgefuehrt' wurde."
    }
    $rootCA = Join-Path $CertDir "rootCA.crt"
    if (-not (Test-Path $rootCA)) {
        throw "$rootCA nicht gefunden. Zuerst Schritt 'certs' ausfuehren."
    }
    Invoke-Native certutil -addstore -f "Root" $rootCA
    Write-Host "Root-Zertifikat wurde als vertrauenswuerdig markiert."
}

function Step-Build {
    Test-Cmd docker "Bitte Docker Desktop installieren und starten."
    Invoke-Native docker build -t tt-site ./malicious-website
}

function Step-Run {
    Test-Cmd docker "Bitte Docker Desktop installieren und starten."
    $certFile = Join-Path $CertDir "server.crt"
    $keyFile = Join-Path $CertDir "server.key"
    if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
        throw "Zertifikate fehlen. Zuerst Schritt 'certs' ausfuehren."
    }
    # Docker erwartet Pfade mit Schraegstrichen, auch unter Windows.
    $cert = (Join-Path (Get-Location) $certFile) -replace '\\', '/'
    $key = (Join-Path (Get-Location) $keyFile) -replace '\\', '/'

    Invoke-Native docker run --rm `
        -p 5002:5002 `
        -v "${cert}:/etc/nginx/certs/server.crt:ro" `
        -v "${key}:/etc/nginx/certs/server.key:ro" `
        tt-site
}

function Step-LoadCA {
    Test-Cmd adb "Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen."
    $rootCA = Join-Path $CertDir "rootCA.crt"
    if (-not (Test-Path $rootCA)) {
        throw "$rootCA nicht gefunden. Zuerst Schritt 'certs' ausfuehren."
    }
    $devices = adb devices | Select-String '\bdevice$'
    if (-not $devices) {
        throw "Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten."
    }
    Invoke-Native adb push $rootCA /sdcard/Download/rootCA.crt
    Write-Host "Im Emulator als naechstes auf:"
    Write-Host "Einstellungen"
    Write-Host "Suchleiste: Ein Zertifikate installieren"
    Write-Host "rootCA aus dem Download Ordner einfuegen"
}

function Step-All {
    Step-Certs
    Step-Trust
    Step-Build
}

$StepMap = @{
    '1' = 'certs'; '2' = 'trust'; '3' = 'build'
    '4' = 'run'; '5' = 'load-ca'; '6' = 'all'
}

function Invoke-Step {
    param([string]$Name)
    switch ($Name) {
        'certs'   { Step-Certs }
        'trust'   { Step-Trust }
        'build'   { Step-Build }
        'run'     { Step-Run }
        'load-ca' { Step-LoadCA }
        'all'     { Step-All }
        default   { throw "Unbekannter Schritt: $Name" }
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "TapTrap Setup (Windows)"
    Write-Host "========================"
    Write-Host " 1) certs    TLS-Zertifikate erzeugen (einmalig)"
    Write-Host " 2) trust    Root-Zertifikat auf diesem Rechner vertrauen (Admin!)"
    Write-Host " 3) build    Webserver-Docker-Image bauen"
    Write-Host " 4) run      Webserver starten (blockierend, Strg+C zum Beenden)"
    Write-Host " 5) load-ca  Root-Zertifikat auf den Emulator laden"
    Write-Host " 6) all      Schritte 1-3 nacheinander ausfuehren"
    Write-Host " 0) exit     Beenden"
}

# Nicht-interaktiv: .\setup.ps1 <schritt>
if ($Step) {
    $resolved = if ($StepMap.ContainsKey($Step)) { $StepMap[$Step] } else { $Step }
    Invoke-Step -Name $resolved
    exit 0
}

# Interaktives Menue
while ($true) {
    Show-Menu
    $choice = Read-Host "Auswahl"
    if ($choice -eq '0' -or $choice -eq 'exit') { break }
    $resolved = if ($StepMap.ContainsKey($choice)) { $StepMap[$choice] } else { $choice }
    try {
        Invoke-Step -Name $resolved
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}
