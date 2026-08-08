# Taptrap Deployment Guide

Dies ist der offizielle Deployment Guide von Taptrap. Er dient als Grundlage und Ergänzung dafür, wie man Taptrap auf einem Pixel-6a-Emulator simulieren kann, um Zugriffsrechte zu erhalten, ohne dass der Benutzer etwas von der Prozedur mitbekommt. Zusätzlich werden Skripte bereitgestellt, welche die Analysen ermöglichen. Dieses Repository soll somit als Ergänzung zur Hausarbeit dienen, sodass interessierten Lesern eine leichtere Nachbildung der Experimente möglich ist.

Diese Anleitung richtet sich auch an Leser ohne viel Vorerfahrung mit Kommandozeile, Docker oder Android-Entwicklung — jeder Schritt wird kurz erklärt, bevor der eigentliche Befehl kommt. Die Anleitung deckt **macOS** (Intel & Apple Silicon), **Ubuntu/Debian** und **Fedora/RHEL** über `setup.sh` sowie **Windows** über `setup.ps1` ab. Andere Linux-Distributionen funktionieren beim Webserver/Emulator-Teil in der Regel ebenfalls, beim Schritt `trust` (Root-Zertifikat vertrauen) muss dort aber manuell nachgeholfen werden.

## Was passiert hier eigentlich?

Für die Demo werden drei Dinge gebraucht:

1. Ein **Android-Emulator**, auf dem die präparierte App installiert wird.
2. Ein **eigener Webserver mit HTTPS**, der die Webseite bereitstellt, die als Vorwand für den Angriff dient. Android verweigert ohne gültiges HTTPS-Zertifikat den Zugriff auf die Seite, deshalb muss ein eigenes Zertifikat erzeugt und sowohl dem eigenen Rechner als auch dem Emulator "beigebracht" werden, dass es vertrauenswürdig ist.
3. Optional: eine auf **Deutsch** umgestellte Systemsprache im Emulator, damit die Demo auf Deutsch abläuft.

Die folgenden Schritte bauen aufeinander auf und sollten in dieser Reihenfolge ausgeführt werden.

## Voraussetzungen

| Werkzeug | macOS | Windows |
|---|---|---|
| Android Studio (inkl. SDK, `adb`) | [Download](https://developer.android.com/studio) | [Download](https://developer.android.com/studio) |
| Docker Desktop | [Download](https://www.docker.com/products/docker-desktop/) | [Download](https://www.docker.com/products/docker-desktop/) (WSL2-Backend empfohlen) |
| OpenSSL | bereits vorinstalliert | über [Git for Windows](https://git-scm.com/download/win) (bringt `openssl.exe` mit) oder `winget install ShiningLight.OpenSSL` |
| Terminal | Terminal.app / iTerm | PowerShell (vorinstalliert) |

Stellt sicher, dass `adb` im `PATH` liegt (Android Studio → Settings → SDK-Verzeichnis, Unterordner `platform-tools`). Ob es funktioniert, lässt sich mit `adb --version` (macOS) bzw. `adb.exe --version` (Windows) prüfen.

### Hinweis für Windows: Skripte ausführen

Windows blockiert das Ausführen von `.ps1`-Dateien standardmäßig. Einmalig in einer **normalen** PowerShell (nicht als Administrator) ausführen:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Skripte, die Änderungen am System vornehmen (Zertifikatsspeicher), müssen zusätzlich **als Administrator** ausgeführt werden — das ist beim jeweiligen Schritt unten vermerkt.

Alle Schritte unten werden über eines von zwei Setup-Skripten ausgeführt: `setup.sh` für macOS/Linux (Terminal) und `setup.ps1` für Windows (PowerShell). Windows-Skripte startet man mit vorangestelltem `.\`, z. B. `.\setup.ps1`.

Beide Skripte lassen sich auf zwei Arten nutzen:

- **Interaktiv:** einfach ohne Argumente aufrufen (`./setup.sh` bzw. `.\setup.ps1`) — es erscheint ein Menü, aus dem der gewünschte Schritt per Nummer oder Name ausgewählt wird.
- **Direkt:** mit dem Schrittnamen als Argument, z. B. `./setup.sh certs` bzw. `.\setup.ps1 certs`. So lassen sich Schritte auch aus eigenen Skripten heraus automatisieren.

Die verfügbaren Schritte sind `certs`, `trust`, `build`, `run`, `load-ca`, `german` und `all` (führt `certs`, `trust` und `build` nacheinander aus) — sie entsprechen genau den Schritten 2–6 weiter unten.

## Schritt-für-Schritt-Anleitung

### 1. Android Studio & Emulator einrichten

Als Emulator sollte ein **Pixel 6a** mit **Android 15** (API Level 35, "VanillaIceCream") und **Google APIs** als Services gewählt werden.

Wählt man stattdessen den Google Play Store als Service, lässt sich die Systemsprache später nicht mehr per `adb` automatisieren (siehe Schritt 5). Ansonsten hat die Wahl keine weitere Bedeutung.

Für die Einrichtung von Android Studio sowie den benötigten `sdkmanager` und `cmdline-tools` sei auf das Referenz-Repository [beerphilipp/taptrap](https://github.com/beerphilipp/taptrap) verwiesen. Startet den Emulator, bevor ihr mit Schritt 5 fortfahrt.

### 2. TLS-Zertifikate erzeugen

*Warum?* Damit der Emulator die eigene Webseite über HTTPS ohne Warnung/Fehler laden kann, braucht der Webserver ein Zertifikat. Da es keine öffentliche Domain gibt, wird eine eigene, kleine Zertifizierungsstelle ("Root CA") erstellt, die anschließend ein Server-Zertifikat für `localhost` signiert.

Die Dateien landen direkt im Ordner `certs/` und müssen **einmalig** erzeugt werden. Sie sind bewusst in `.gitignore` eingetragen und werden nicht ins Repository übernommen.

**macOS:**
```bash
./setup.sh certs
```

**Windows:**
```powershell
.\setup.ps1 certs
```

Am Ende sollte die Zeile `server.crt: OK` erscheinen. Erscheint sie nicht, stimmt etwas mit der Zertifikatskette nicht — in diesem Fall nicht mit den nächsten Schritten fortfahren, sondern den Fehler oben in der Ausgabe suchen.

### 3. Root-Zertifikat auf dem eigenen Rechner vertrauen

*Warum?* Der Browser/das System muss der selbst erstellten Root CA vertrauen, damit man die Webseite z. B. auch lokal im Browser ohne Zertifikatswarnung öffnen kann.

**macOS** (fragt nach dem Login-Passwort):
```bash
./setup.sh trust
```

**Windows** (PowerShell **als Administrator** öffnen, dann):
```powershell
.\setup.ps1 trust
```

Unter Linux wird sowohl Ubuntu/Debian (`update-ca-certificates`) als auch Fedora/RHEL (`update-ca-trust`) unterstützt; das passende Werkzeug wird automatisch erkannt. Bei anderen Distributionen muss `certs/rootCA.crt` manuell in den System-Zertifikatsspeicher importiert werden.

### 4. Webserver bauen und starten

*Warum?* Die präparierte Webseite läuft in einem nginx-Container, der über Docker gebaut und gestartet wird. Docker sorgt dafür, dass es unabhängig vom Betriebssystem immer gleich funktioniert.

Docker Desktop muss vorher gestartet sein.

**macOS:**
```bash
./setup.sh build
./setup.sh run
```

**Windows:**
```powershell
.\setup.ps1 build
.\setup.ps1 run
```

Der Webserver läuft anschließend erreichbar unter `https://localhost:5002` und im Emulator unter `https://10.0.2.2:5002` (das ist die Adresse, unter der der Emulator den Host-Rechner erreicht). Zum Beenden reicht `Strg+C` im selben Terminal-Fenster.

### 5. Root-Zertifikat auf den Emulator laden

*Warum?* Auch der Emulator selbst muss der Root CA vertrauen, sonst blockiert Android die HTTPS-Verbindung zur eigenen Webseite.

Emulator muss laufen, bevor dieser Schritt ausgeführt wird.

**macOS:**
```bash
./setup.sh load-ca
```

**Windows:**
```powershell
.\setup.ps1 load-ca
```

Das Skript kopiert das Zertifikat in den Download-Ordner des Emulators und zeigt an, wo es im Emulator manuell importiert werden muss: **Einstellungen → Suchleiste → "Zertifikate installieren" → Datei aus dem Download-Ordner wählen.**

Wird der Emulator zurückgesetzt (z. B. über "Wipe Data"), geht der Import verloren und dieser Schritt muss wiederholt werden.

### 6. (Optional) Emulator-Sprache auf Deutsch stellen

Nur nötig, wenn die Demo auf Deutsch laufen soll und **Google APIs** (nicht Play Store) als Emulator-Service gewählt wurde (siehe Schritt 1).

**macOS:**
```bash
./setup.sh german
```

**Windows:**
```powershell
.\setup.ps1 german
```

Das Skript findet den laufenden Emulator automatisch. Laufen mehrere Emulatoren gleichzeitig, kann die Seriennummer explizit angegeben werden, z. B. `./setup.sh german emulator-5556` bzw. `.\setup.ps1 german emulator-5556` (Seriennummer mit `adb devices` herausfinden).

### 7. App testen

Sobald der Webserver läuft (Schritt 4) und der Emulator dem Zertifikat vertraut (Schritt 5), kann die App aus Android Studio auf den Emulator installiert und die Demo durchlaufen werden. Die Ziel-URL ist in

```
KillTheBugs/app/src/main/res/values/strings.xml
```

hinterlegt:

```xml
<resources>
    <string name="app_name">ToeteDieKaefer</string>
    <string name="webapp">https://killthebugs.taptrap.click/</string>
    <string name="pivotY_Pixel6a">57.75%</string>
    <string name="pivotY_Edge20">56%</string>
</resources>
```

Für den eigenen, lokalen Webserver aus Schritt 4 den Wert von `webapp` auf `https://10.0.2.2:5002` ändern. Das ist praktisch, wenn man den Emulator häufiger zurücksetzt und die Demo ohne den öffentlichen Server erneut sauber durchlaufen lassen möchte. Danach wieder zurück auf `https://killthebugs.taptrap.click/` wechseln, sobald man mit den Ergebnissen zufrieden ist.

## Fehlerbehebung

- **"docker: command not found" / "Cannot connect to the Docker daemon"** — Docker Desktop ist nicht installiert oder nicht gestartet.
- **PowerShell verweigert die Ausführung eines `.ps1`-Skripts** — siehe [Hinweis für Windows](#hinweis-für-windows-skripte-ausführen) oben.
- **`certutil` schlägt ohne klare Fehlermeldung fehl** — PowerShell wurde nicht als Administrator gestartet.
- **Zertifikatsfehler im Emulator-Browser trotz Import** — Emulator wurde zwischenzeitlich zurückgesetzt ("Wipe Data"); Schritt 5 erneut ausführen.
- **`adb` erkennt keinen Emulator** — Emulator ist nicht gestartet, oder `adb` liegt nicht im `PATH`.

## Entwicklung

Die gesamte Setup-Logik steckt in genau zwei Dateien: `setup.sh` (macOS/Linux) und `setup.ps1` (Windows). Beide bilden dieselben sieben Schritte (`certs`, `trust`, `build`, `run`, `load-ca`, `german`, `all`) als Funktionen ab, die entweder über das interaktive Menü oder direkt per Argument aufgerufen werden. Wer einen Schritt ändert oder einen neuen hinzufügt, sollte das jeweils in beiden Dateien tun, damit macOS/Linux und Windows im Funktionsumfang gleichauf bleiben.

`setup.sh` benötigt das Ausführungsrecht (`chmod +x setup.sh`) — im Repository ist das bereits gesetzt.
