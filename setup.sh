#!/bin/bash
# Interactive setup helper for macOS/Linux. Run without arguments for a menu,
# or pass a step name directly, e.g. `./setup.sh certs` or `./setup.sh transparency hide`.
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

step_load_ca() {
  need adb "Bitte den Android SDK platform-tools Ordner zum PATH hinzufuegen." || return 1
  if [ ! -f "$CERT_DIR/rootCA.crt" ]; then
    echo "Fehler: $CERT_DIR/rootCA.crt nicht gefunden. Zuerst Schritt 'certs' ausfuehren." >&2
    return 1
  fi
  if [ -z "$(adb devices | awk 'NR>1 && $2=="device" {print $1}')" ]; then
    echo "Fehler: Kein laufender Emulator gefunden. Bitte zuerst den Emulator in Android Studio starten." >&2
    return 1
  fi
  adb push "$CERT_DIR/rootCA.crt" /sdcard/Download/rootCA.crt
  echo "Im Emulator als naechstes auf:"
  echo "Einstellungen"
  echo "Suchleiste: Ein Zertifikate installieren"
  echo "rootCA aus dem Download Ordner einfuegen"
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
TRANSPARENCY_HIDE_ALPHA="0.02"
TRANSPARENCY_SHOW_ALPHA="1.0"

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
    echo "  show  Voll sichtbar (alpha=$TRANSPARENCY_SHOW_ALPHA) - zeigt dem Publikum den echten Systemdialog im Hintergrund"
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

step_all() {
  step_certs && step_trust && step_build
}

run_step() {
  case "$1" in
    1|certs)   step_certs ;;
    2|trust)   step_trust ;;
    3|build)   step_build ;;
    4|run)     step_run ;;
    5|load-ca) step_load_ca ;;
    6|transparency) shift; step_transparency "${1:-}" ;;
    7|all)     step_all ;;
    *) echo "Unbekannter Schritt: $1" >&2; return 1 ;;
  esac
}

print_menu() {
  cat <<'EOF'

TapTrap Setup (macOS/Linux)
============================
 1) certs        TLS-Zertifikate erzeugen (einmalig)
 2) trust        Root-Zertifikat auf diesem Rechner vertrauen
 3) build        Webserver-Docker-Image bauen
 4) run          Webserver starten (blockierend, Strg+C zum Beenden)
 5) load-ca      Root-Zertifikat auf den Emulator laden
 6) transparency Deckkraft der Tarn-Animation fuer Demo-Zwecke anpassen
 7) all          Schritte 1-3 nacheinander ausfuehren
 0) exit         Beenden
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
