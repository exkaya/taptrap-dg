#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

command -v adb >/dev/null || { echo "adb wurde nicht gefunden. Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." >&2; exit 1; }

if [ ! -f "certs/rootCA.crt" ]; then
  echo "certs/rootCA.crt wurde nicht gefunden. Bitte zuerst certs/build_cert_chain.sh ausfuehren." >&2
  exit 1
fi

if [ -z "$(adb devices | awk 'NR>1 && $2=="device" {print $1}')" ]; then
  echo "Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
  exit 1
fi

adb push certs/rootCA.crt /sdcard/Download/rootCA.crt

echo "Im Emulator als naechstes auf:"
echo "Einstellungen"
echo "Suchleiste: Ein Zertifikate installieren"
echo "rootCA aus dem Download Ordner einfuegen"
