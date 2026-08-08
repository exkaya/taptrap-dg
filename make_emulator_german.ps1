param(
    # Optionale Emulator-Seriennummer, z.B. .\make_emulator_german.ps1 -Serial emulator-5556
    [string]$Serial
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "adb wurde nicht gefunden. Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen."
}

if (-not $Serial) {
    $match = adb devices | Select-String '^emulator-\S+' | Select-Object -First 1
    if ($match) { $Serial = ($match.Line -split '\s+')[0] }
}

if (-not $Serial) {
    throw "Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten."
}

Write-Host "Verwende Emulator: $Serial"

adb -s $Serial root
adb -s $Serial wait-for-device
adb -s $Serial shell "setprop persist.sys.locale de-DE; stop; sleep 5; start"
adb -s $Serial wait-for-device
adb -s $Serial shell getprop persist.sys.locale
