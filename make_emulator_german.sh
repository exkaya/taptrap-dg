#!/bin/bash
set -euo pipefail

command -v adb >/dev/null || { echo "adb wurde nicht gefunden. Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." >&2; exit 1; }

# Emulator-Seriennummer kann als erstes Argument angegeben werden, z.B. ./make_emulator_german.sh emulator-5556
SERIAL="${1:-$(adb devices | awk '/^emulator-/{print $1; exit}')}"

if [ -z "$SERIAL" ]; then
  echo "Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
  exit 1
fi

echo "Verwende Emulator: $SERIAL"

adb -s "$SERIAL" root
adb -s "$SERIAL" wait-for-device
adb -s "$SERIAL" shell "setprop persist.sys.locale de-DE; stop; sleep 5; start"
adb -s "$SERIAL" wait-for-device
adb -s "$SERIAL" shell getprop persist.sys.locale
