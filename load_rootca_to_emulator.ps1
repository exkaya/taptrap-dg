$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "adb wurde nicht gefunden. Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen."
}

if (-not (Test-Path "certs\rootCA.crt")) {
    throw "certs\rootCA.crt wurde nicht gefunden. Bitte zuerst certs\build_cert_chain.ps1 ausfuehren."
}

$devices = adb devices | Select-String '\bdevice$'
if (-not $devices) {
    throw "Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten."
}

adb push certs/rootCA.crt /sdcard/Download/rootCA.crt

Write-Host "Im Emulator als naechstes auf:"
Write-Host "Einstellungen"
Write-Host "Suchleiste: Ein Zertifikate installieren"
Write-Host "rootCA aus dem Download Ordner einfuegen"
