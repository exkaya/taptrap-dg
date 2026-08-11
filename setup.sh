#!/bin/bash
# Interactive setup helper for macOS/Linux. Run without arguments for a menu,
# or pass a step name directly, e.g. `./setup.sh certs` or `./setup.sh transparency hide`.
# Run `./setup.sh --help` for the full list of steps and their arguments.
set -euo pipefail
cd "$(dirname "$0")"

CERT_DIR="certs"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Fehler: '$1' wurde nicht gefunden. $2" >&2
    return 1
  fi
}

# Docker Desktop on macOS ships its credential helper (docker-credential-desktop)
# under Docker.app instead of installing it into PATH. Without it, every `docker`
# command that touches a registry fails with "docker-credential-desktop not found",
# even for public images. Add it to PATH if it's missing but present locally.
fix_docker_creds_path() {
  command -v docker-credential-desktop >/dev/null 2>&1 && return 0
  for d in "/Applications/Docker.app/Contents/Resources/bin" "$HOME/.docker/bin"; do
    if [ -x "$d/docker-credential-desktop" ]; then
      export PATH="$d:$PATH"
      return 0
    fi
  done
}

step_certs() {
  need openssl "Bitte installieren." || return 1
  mkdir -p "$CERT_DIR"
  (
    cd "$CERT_DIR"

    echo "Erstelle Root CA's private key"
    openssl genrsa -out rootCA.key 4096

    echo "Erstelle Root CA's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
    cat > rootCA.cnf <<'EOF'
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
EOF

    echo "Erstelle Root CA Zertifikat mithilfe des private key und der Konfigurationsdatei"
    openssl req -x509 -new -key rootCA.key -sha256 -days 3650 -out rootCA.crt -config rootCA.cnf

    echo "Erstelle Server's private key"
    openssl genrsa -out server.key 2048

    echo "Erstelle Server's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
    cat > server.cnf <<'EOF'
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
EOF

    echo "Erstelle Certificate Signing Request"
    openssl req -new -key server.key -out server.csr -config server.cnf

    echo "Signiere Server's Certificate Signing Request mit dem Root CA"
    openssl x509 -req -in server.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile server.cnf -extensions v3_req

    echo "Verifiziere die Zertifizierungskette (sollte 'server.crt: OK' ausgeben)"
    openssl verify -CAfile rootCA.crt server.crt
  )
}

step_trust() {
  if [ ! -f "$CERT_DIR/rootCA.crt" ]; then
    echo "Fehler: $CERT_DIR/rootCA.crt nicht gefunden. Zuerst Schritt 'certs' ausfuehren." >&2
    return 1
  fi
  case "$(uname -s)" in
    Darwin)
      sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_DIR/rootCA.crt"
      ;;
    Linux)
      if command -v update-ca-certificates >/dev/null 2>&1; then
        # Debian/Ubuntu
        sudo cp "$CERT_DIR/rootCA.crt" /usr/local/share/ca-certificates/taptrap-rootCA.crt
        sudo update-ca-certificates
      elif command -v update-ca-trust >/dev/null 2>&1; then
        # Fedora/RHEL
        sudo cp "$CERT_DIR/rootCA.crt" /etc/pki/ca-trust/source/anchors/taptrap-rootCA.crt
        sudo update-ca-trust
      else
        echo "Fehler: Weder update-ca-certificates noch update-ca-trust gefunden. Root-Zertifikat manuell importieren: $CERT_DIR/rootCA.crt" >&2
        return 1
      fi
      ;;
    *)
      echo "Fehler: Unbekanntes Betriebssystem $(uname -s)." >&2
      return 1
      ;;
  esac
}

step_build() {
  need docker "Bitte Docker Desktop installieren und starten." || return 1
  fix_docker_creds_path
  docker build -t tt-site ./malicious-website
}

step_run() {
  need docker "Bitte Docker Desktop installieren und starten." || return 1
  fix_docker_creds_path
  if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    echo "Fehler: Zertifikate fehlen. Zuerst Schritt 'certs' ausfuehren." >&2
    return 1
  fi
  docker run --rm \
    -p 5002:5002 \
    -v "$PWD/$CERT_DIR/server.crt:/etc/nginx/certs/server.crt:ro" \
    -v "$PWD/$CERT_DIR/server.key:/etc/nginx/certs/server.key:ro" \
    tt-site
}

step_load_ca_manual() {
  local serial="$1"
  adb -s "$serial" push "$CERT_DIR/rootCA.crt" /sdcard/Download/rootCA.crt
  echo "Im Emulator manuell installieren:"
  echo "Einstellungen"
  echo "Suchleiste: Ein Zertifikate installieren"
  echo "rootCA aus dem Download Ordner einfuegen"
}

step_load_ca() {
  need adb "Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." || return 1
  need openssl "Bitte installieren." || return 1
  if [ ! -f "$CERT_DIR/rootCA.crt" ]; then
    echo "Fehler: $CERT_DIR/rootCA.crt nicht gefunden. Zuerst Schritt 'certs' ausfuehren." >&2
    return 1
  fi
  local serial
  serial="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [ -z "$serial" ]; then
    echo "Fehler: Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
    return 1
  fi

  echo "Versuche automatische Installation als System-CA (benoetigt Root, nur auf Google-APIs-Emulatoren moeglich)..."
  if ! adb -s "$serial" root >/dev/null 2>&1; then
    echo "Warnung: 'adb root' fehlgeschlagen (Play-Store-Image oder physisches Geraet?). Falle zurueck auf manuelle Installation." >&2
    step_load_ca_manual "$serial"
    return 0
  fi
  adb -s "$serial" wait-for-device
  if ! adb -s "$serial" remount >/dev/null 2>&1; then
    echo "Warnung: 'adb remount' fehlgeschlagen. Falle zurueck auf manuelle Installation." >&2
    step_load_ca_manual "$serial"
    return 0
  fi

  local hash
  hash="$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_DIR/rootCA.crt" -noout)"
  adb -s "$serial" push "$CERT_DIR/rootCA.crt" "/system/etc/security/cacerts/$hash.0"
  adb -s "$serial" shell chmod 644 "/system/etc/security/cacerts/$hash.0"
  echo "Zertifikat als System-CA installiert (Hash: $hash)."
  echo "Emulator wird neu gestartet, damit die Aenderung wirksam wird..."
  adb -s "$serial" reboot
  adb -s "$serial" wait-for-device
  echo "Fertig. Root-CA ist jetzt systemweit vertrauenswuerdig, kein manueller Import mehr noetig."
}

step_wipe_data() {
  need adb "Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." || return 1
  local serial
  serial="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [ -z "$serial" ]; then
    echo "Fehler: Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
    return 1
  fi

  local avd
  avd="$(adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
  if [ -z "$avd" ]; then
    echo "Fehler: AVD-Name konnte nicht ermittelt werden (kein Emulator, sondern physisches Geraet?)." >&2
    return 1
  fi

  if [ "${1:-}" != "yes" ]; then
    echo "Das setzt den Emulator '$avd' komplett zurueck: installierte App, System-CA und alle Daten gehen verloren."
    read -rp "Wirklich fortfahren? [y/N] " confirm
    case "$confirm" in
      y|Y|yes|Yes) ;;
      *) echo "Abgebrochen."; return 1 ;;
    esac
  fi

  local emulator_bin
  emulator_bin="$(command -v emulator || true)"
  if [ -z "$emulator_bin" ]; then
    for d in "${ANDROID_HOME:-}/emulator/emulator" "${ANDROID_SDK_ROOT:-}/emulator/emulator" "$HOME/Library/Android/sdk/emulator/emulator" "$HOME/Android/Sdk/emulator/emulator"; do
      if [ -n "$d" ] && [ -x "$d" ]; then
        emulator_bin="$d"
        break
      fi
    done
  fi
  if [ -z "$emulator_bin" ]; then
    echo "Fehler: 'emulator'-Binary nicht gefunden. Bitte \$ANDROID_HOME/emulator zum PATH hinzufuegen." >&2
    return 1
  fi

  echo "Stoppe Emulator '$avd' ($serial)..."
  adb -s "$serial" emu kill
  sleep 2
  echo "Starte Emulator '$avd' mit -wipe-data neu..."
  nohup "$emulator_bin" -avd "$avd" -wipe-data >/dev/null 2>&1 &
  disown
  echo "Emulator startet im Hintergrund neu. Mit 'adb wait-for-device' bzw. in Android Studio den Bootvorgang abwarten,"
  echo "danach 'load-ca' erneut ausfuehren, um die Root-CA wieder zu installieren."
}

KILLTHEBUGS_PACKAGE="com.taptrap.userstudy.killthebugs"
# Levels 1+2 run their exploit through a Chrome Custom Tab, so a granted camera/
# location permission belongs to Chrome's own process, not to KillTheBugs -
# checking the KillTheBugs package here would always show "not granted" even
# after a successful exploit.
CHROME_PACKAGE="com.android.chrome"

step_check_permissions() {
  need adb "Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." || return 1
  if [ -z "$(adb devices | awk 'NR>1 && $2=="device" {print $1}')" ]; then
    echo "Fehler: Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
    return 1
  fi

  echo "Laufzeitberechtigungen fuer $CHROME_PACKAGE (Kamera/Standort aus den Leveln 1+2):"
  echo "(Die Custom-Tab-Exploits laufen in Chrome, daher landen erteilte Berechtigungen bei Chrome, nicht bei $KILLTHEBUGS_PACKAGE.)"
  local dump runtime_perms
  dump="$(adb shell dumpsys package "$CHROME_PACKAGE" 2>/dev/null || true)"
  if [ -z "$dump" ]; then
    echo "  Keine Angaben gefunden - ist Chrome installiert? (Paket: $CHROME_PACKAGE)"
  else
    runtime_perms="$(printf '%s\n' "$dump" | sed -n '/runtime permissions:/,/^$/p' | grep -E '\.CAMERA:|\.ACCESS_FINE_LOCATION:|\.ACCESS_COARSE_LOCATION:' | sort -u || true)"
    if [ -z "$runtime_perms" ]; then
      echo "  Keine Kamera-/Standort-Berechtigung angefragt oder erteilt."
    else
      echo "$runtime_perms" | sed 's/^/  /'
    fi
  fi

  echo ""
  echo "Geraeteadministrator-Status (aus Level 3):"
  local admin_status
  admin_status="$(adb shell dumpsys device_policy 2>/dev/null | grep -i "$KILLTHEBUGS_PACKAGE" || true)"
  if [ -z "$admin_status" ]; then
    echo "  $KILLTHEBUGS_PACKAGE ist aktuell KEIN Geraeteadministrator."
  else
    echo "  $KILLTHEBUGS_PACKAGE ist als Geraeteadministrator aktiv:"
    echo "$admin_status" | sed 's/^/  /'
  fi
}

# Animation-Ressourcen, die den echten System-Dialog waehrend des Exploits per
# fixem Alpha-Wert verdecken (siehe KillTheBugs/app/src/main/java/.../LevelActivity.kt,
# exploitCustomTab/exploitDeviceManager). Fuer Vorfuehrungen laesst sich dieser Wert
# hier umschalten, ohne die XML-Dateien manuell zu editieren.
TRANSPARENCY_ANIM_DIR="KillTheBugs/app/src/main/res/anim"
TRANSPARENCY_ANIM_FILES=(
  fade_in_ct_location.xml
  fade_in_ct_location_admin.xml
  fade_in_ct_camera.xml
  fade_in_ct_camera_admin.xml
  fade_in_dmp.xml
  fade_in_dmp_admin.xml
)

# "hide" ist bewusst nicht 0.0: der Systemdialog soll fuer den echten Angriff
# fuer das menschliche Auge quasi unsichtbar bleiben, aber technisch vorhanden.
# "show" ist bewusst nicht 1.0: bei voller Deckkraft ueberlagert der Systemdialog
# das Spiel komplett, die Kaefer sind dann nicht mehr zu sehen. 0.5 war der
# urspruengliche Wert und zeigt fuer Vorfuehrungen beides gleichzeitig.
TRANSPARENCY_HIDE_ALPHA="0.02"
TRANSPARENCY_SHOW_ALPHA="0.5"

step_transparency() {
  local mode="${1:-}"

  if [ -z "$mode" ]; then
    echo "Aktuelle Deckkraft (Alpha) der Tarn-Animationen:"
    for f in "${TRANSPARENCY_ANIM_FILES[@]}"; do
      local path="$TRANSPARENCY_ANIM_DIR/$f"
      if [ -f "$path" ]; then
        local alpha
        alpha="$(grep -m1 -o 'android:fromAlpha="[0-9.]*"' "$path" | grep -o '[0-9.]*')"
        echo "  $f: $alpha"
      fi
    done
    echo ""
    echo "Verwendung: ./setup.sh transparency <show|hide>"
    echo "  show  Mittel sichtbar (alpha=$TRANSPARENCY_SHOW_ALPHA) - zeigt dem Publikum den echten Systemdialog im Hintergrund, Kaefer bleiben sichtbar"
    echo "  hide  Fuer das Auge quasi unsichtbar (alpha=$TRANSPARENCY_HIDE_ALPHA) - wie im echten, verdeckten Angriff"
    return 0
  fi

  local value
  case "$mode" in
    show) value="$TRANSPARENCY_SHOW_ALPHA" ;;
    hide) value="$TRANSPARENCY_HIDE_ALPHA" ;;
    *)
      echo "Fehler: Unbekannter Modus '$mode'. Erlaubt: 'show' oder 'hide'." >&2
      return 1
      ;;
  esac

  for f in "${TRANSPARENCY_ANIM_FILES[@]}"; do
    local path="$TRANSPARENCY_ANIM_DIR/$f"
    if [ ! -f "$path" ]; then
      echo "Warnung: $path nicht gefunden, ueberspringe." >&2
      continue
    fi
    case "$(uname -s)" in
      Darwin)
        sed -i '' -E "s/android:fromAlpha=\"[0-9.]+\"/android:fromAlpha=\"$value\"/; s/android:toAlpha=\"[0-9.]+\"/android:toAlpha=\"$value\"/" "$path"
        ;;
      *)
        sed -i -E "s/android:fromAlpha=\"[0-9.]+\"/android:fromAlpha=\"$value\"/; s/android:toAlpha=\"[0-9.]+\"/android:toAlpha=\"$value\"/" "$path"
        ;;
    esac
    echo "Aktualisiert: $f -> alpha=$value"
  done

  echo ""
  echo "Hinweis: Die KillTheBugs-App muss neu gebaut und auf dem Emulator installiert werden,"
  echo "damit die Aenderung sichtbar wird (Android Studio: Run, oder 'cd KillTheBugs && ./gradlew installDebug')."
}

# Die Ziel-URL der App steckt fest in strings.xml (kein Emulator-Netzwerkzugriff
# auf lokale Hostnamen, deshalb kein setup.sh-Argument zur Laufzeit). Fuer den
# Wechsel zwischen "lokal testen" und "oeffentliche Demo-Seite" hier umschaltbar,
# ohne die XML-Datei manuell zu editieren.
WEBAPP_STRINGS_FILE="KillTheBugs/app/src/main/res/values/strings.xml"
WEBAPP_LOCAL_URL="https://10.0.2.2:5002"
WEBAPP_REMOTE_URL="https://killthebugs.taptrap.click/"

step_webapp() {
  local mode="${1:-}"

  if [ ! -f "$WEBAPP_STRINGS_FILE" ]; then
    echo "Fehler: $WEBAPP_STRINGS_FILE nicht gefunden." >&2
    return 1
  fi

  if [ -z "$mode" ]; then
    echo "Aktuelle webapp-URL:"
    grep -o '<string name="webapp">[^<]*</string>' "$WEBAPP_STRINGS_FILE" | sed -E 's#.*>([^<]*)<.*#  \1#'
    echo ""
    echo "Verwendung: ./setup.sh webapp <local|remote>"
    echo "  local   Lokaler Webserver ($WEBAPP_LOCAL_URL) - fuer 'build'/'run' (Schritt 4)"
    echo "  remote  Oeffentliche Demo-Seite ($WEBAPP_REMOTE_URL)"
    return 0
  fi

  local url
  case "$mode" in
    local)  url="$WEBAPP_LOCAL_URL" ;;
    remote) url="$WEBAPP_REMOTE_URL" ;;
    *)
      echo "Fehler: Unbekannter Modus '$mode'. Erlaubt: 'local' oder 'remote'." >&2
      return 1
      ;;
  esac

  case "$(uname -s)" in
    Darwin)
      sed -i '' -E "s#(<string name=\"webapp\">)[^<]*(</string>)#\1${url}\2#" "$WEBAPP_STRINGS_FILE"
      ;;
    *)
      sed -i -E "s#(<string name=\"webapp\">)[^<]*(</string>)#\1${url}\2#" "$WEBAPP_STRINGS_FILE"
      ;;
  esac
  echo "webapp-URL gesetzt auf: $url"
  echo ""
  echo "Hinweis: Die KillTheBugs-App muss neu gebaut und auf dem Emulator installiert werden,"
  echo "damit die Aenderung wirksam wird (Android Studio: Run, oder 'cd KillTheBugs && ./gradlew installDebug')."
  if [ "$mode" = "local" ]; then
    echo "Fuer 'local' muss ausserdem der Webserver laufen ('./setup.sh run') und der Emulator der Root-CA vertrauen ('./setup.sh load-ca')."
  fi
}

step_all() {
  step_certs && step_trust && step_build
}

run_step() {
  case "$1" in
    1|certs)             step_certs ;;
    2|trust)             step_trust ;;
    3|build)             step_build ;;
    4|run)               step_run ;;
    5|wipe-data)         shift; step_wipe_data "${1:-}" ;;
    6|load-ca)           step_load_ca ;;
    7|check-permissions) step_check_permissions ;;
    8|transparency)      shift; step_transparency "${1:-}" ;;
    9|webapp)            shift; step_webapp "${1:-}" ;;
    10|all)              step_all ;;
    h|-h|--help|help)    print_help ;;
    *) echo "Unbekannter Schritt: $1" >&2; return 1 ;;
  esac
}

print_menu() {
  cat <<'EOF'

TapTrap Setup (macOS/Linux)
============================
 1) certs             TLS-Zertifikate erzeugen (einmalig)
 2) trust             Root-Zertifikat auf diesem Rechner vertrauen
 3) build             Webserver-Docker-Image bauen
 4) run               Webserver starten (blockierend, Strg+C zum Beenden)
 5) wipe-data         Emulator auf Werkszustand zuruecksetzen (optional)
 6) load-ca           Root-Zertifikat auf den Emulator laden (automatisch, mit manuellem Fallback)
 7) check-permissions Erteilte Berechtigungen/Geraeteadmin-Status der App pruefen
 8) transparency      Deckkraft der Tarn-Animation fuer Demo-Zwecke anpassen
 9) webapp            Zwischen lokaler und oeffentlicher Ziel-URL wechseln
10) all               Schritte 1-3 nacheinander ausfuehren
 h) help              Diese Hilfe mit allen Argumenten anzeigen (./setup.sh --help)
 0) exit              Beenden
EOF
}

print_help() {
  cat <<'EOF'
TapTrap Setup (macOS/Linux) - Hilfe
====================================

Verwendung:
  ./setup.sh                    Interaktives Menue (Schritt per Nummer oder Name waehlen)
  ./setup.sh <schritt> [arg]    Schritt direkt ausfuehren, z. B. aus eigenen Skripten heraus

Schritte:
  certs                      TLS-Zertifikate erzeugen (einmalig)
  trust                      Root-Zertifikat auf diesem Rechner vertrauen
  build                      Webserver-Docker-Image bauen
  run                        Webserver starten (blockierend, Strg+C zum Beenden)
  wipe-data [yes]            Emulator auf Werkszustand zuruecksetzen (optional)
                             'yes' ueberspringt die Sicherheitsabfrage
  load-ca                    Root-Zertifikat auf den Emulator laden
                             (automatisch als System-CA, mit manuellem Fallback)
  check-permissions          Erteilte Berechtigungen/Geraeteadmin-Status der App pruefen
  transparency [show|hide]   Deckkraft der Tarn-Animation umschalten
                             ohne Argument: zeigt die aktuell gesetzten Werte an
  webapp [local|remote]      Zwischen lokaler und oeffentlicher Ziel-URL wechseln
                             ohne Argument: zeigt die aktuell gesetzte URL an
  all                        certs, trust und build nacheinander ausfuehren
  --help, -h, help           Diese Hilfe anzeigen

Jeder Schritt laesst sich auch ueber seine Menuenummer aufrufen, z. B. './setup.sh 8 show'.

Beispiele:
  ./setup.sh
  ./setup.sh certs
  ./setup.sh transparency hide
  ./setup.sh transparency show
  ./setup.sh webapp remote
  ./setup.sh wipe-data yes

Details zu jedem Schritt: siehe README.md.
EOF
}

# Nicht-interaktiv: ./setup.sh <schritt> [argumente...]
if [ "$#" -gt 0 ]; then
  run_step "$@"
  exit $?
fi

# Interaktives Menue
while true; do
  print_menu
  read -rp "Auswahl: " choice
  case "$choice" in
    0|exit|quit) break ;;
    *) run_step "$choice" || true ;;
  esac
done
