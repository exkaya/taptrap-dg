# Taptrap Deployment Guide

Dies ist der offizielle Deployment Guide von Taptrap. Er dient als Grundlage und Ergänzung dafür, wie man Taptrap auf einem Pixel-6a-Emulator simulieren kann, um Zugriffsrechte zu erhalten, ohne dass der Benutzer etwas von der Prozedur mitbekommt. Zusätzlich werden Skripte bereitgestellt, welche die Analysen ermöglichen. Dieses Repository soll somit als Ergänzung zur Hausarbeit dienen, sodass interessierten Lesern eine leichtere Nachbildung der Experimente möglich ist.

Diese Anleitung richtet sich auch an Leser ohne viel Vorerfahrung mit Kommandozeile, Docker oder Android-Entwicklung — jeder Schritt wird kurz erklärt, bevor der eigentliche Befehl kommt. Die Anleitung deckt **macOS** und **Windows** ab; für Linux funktionieren die `.sh`-Skripte in der Regel unverändert, wurden aber nicht getestet.

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

Für jeden Schritt gibt es zwei gleichwertige Skript-Varianten im Repository: `name.sh` für macOS/Linux (Terminal) und `name.ps1` für Windows (PowerShell). Windows-Skripte startet man mit vorangestelltem `.\`, z. B. `.\build_webserver.ps1`.

## Schritt-für-Schritt-Anleitung

### 1. Android Studio & Emulator einrichten

Als Emulator sollte ein **Pixel 6a** mit **Android 15** (API Level 35, "VanillaIceCream") und **Google APIs** als Services gewählt werden.

Wählt man stattdessen den Google Play Store als Service, lässt sich die Systemsprache später nicht mehr per `adb` automatisieren (siehe Schritt 5). Ansonsten hat die Wahl keine weitere Bedeutung.

Für die Einrichtung von Android Studio sowie den benötigten `sdkmanager` und `cmdline-tools` sei auf das Referenz-Repository [beerphilipp/taptrap](https://github.com/beerphilipp/taptrap) verwiesen. Startet den Emulator, bevor ihr mit Schritt 5 fortfahrt.

### 2. TLS-Zertifikate erzeugen

*Warum?* Damit der Emulator die eigene Webseite über HTTPS ohne Warnung/Fehler laden kann, braucht der Webserver ein Zertifikat. Da es keine öffentliche Domain gibt, wird eine eigene, kleine Zertifizierungsstelle ("Root CA") erstellt, die anschließend ein Server-Zertifikat für `localhost` signiert.

Das Skript legt die Dateien direkt im Ordner `certs/` ab (das Verzeichnis, in dem es liegt) und muss **einmalig** ausgeführt werden. Die erzeugten Dateien (`*.key`, `*.crt`, …) sind bewusst in `.gitignore` eingetragen und werden nicht ins Repository übernommen.

**macOS:**
```bash
./certs/build_cert_chain.sh
```

**Windows:**
```powershell
.\certs\build_cert_chain.ps1
```

Am Ende sollte die Zeile `server.crt: OK` erscheinen. Erscheint sie nicht, stimmt etwas mit der Zertifikatskette nicht — in diesem Fall nicht mit den nächsten Schritten fortfahren, sondern den Fehler oben in der Ausgabe suchen.

### 3. Root-Zertifikat auf dem eigenen Rechner vertrauen

*Warum?* Der Browser/das System muss der selbst erstellten Root CA vertrauen, damit man die Webseite z. B. auch lokal im Browser ohne Zertifikatswarnung öffnen kann.

**macOS** (fragt nach dem Login-Passwort):
```bash
./mac_make_rootca_trusted.sh
```

**Windows** (PowerShell **als Administrator** öffnen, dann):
```powershell
.\windows_make_rootca_trusted.ps1
```

### 4. Webserver bauen und starten

*Warum?* Die präparierte Webseite läuft in einem nginx-Container, der über Docker gebaut und gestartet wird. Docker sorgt dafür, dass es unabhängig vom Betriebssystem immer gleich funktioniert.

Docker Desktop muss vorher gestartet sein.

**macOS:**
```bash
./build_webserver.sh
./run_webserver.sh
```

**Windows:**
```powershell
.\build_webserver.ps1
.\run_webserver.ps1
```

Der Webserver läuft anschließend erreichbar unter `https://localhost:5002` und im Emulator unter `https://10.0.2.2:5002` (das ist die Adresse, unter der der Emulator den Host-Rechner erreicht). Zum Beenden reicht `Strg+C` im selben Terminal-Fenster.

### 5. Root-Zertifikat auf den Emulator laden

*Warum?* Auch der Emulator selbst muss der Root CA vertrauen, sonst blockiert Android die HTTPS-Verbindung zur eigenen Webseite.

Emulator muss laufen, bevor dieser Schritt ausgeführt wird.

**macOS:**
```bash
./load_rootca_to_emulator.sh
```

**Windows:**
```powershell
.\load_rootca_to_emulator.ps1
```

Das Skript kopiert das Zertifikat in den Download-Ordner des Emulators und zeigt an, wo es im Emulator manuell importiert werden muss: **Einstellungen → Suchleiste → "Zertifikate installieren" → Datei aus dem Download-Ordner wählen.**

Wird der Emulator zurückgesetzt (z. B. über "Wipe Data"), geht der Import verloren und dieser Schritt muss wiederholt werden.

### 6. (Optional) Emulator-Sprache auf Deutsch stellen

Nur nötig, wenn die Demo auf Deutsch laufen soll und **Google APIs** (nicht Play Store) als Emulator-Service gewählt wurde (siehe Schritt 1).

**macOS:**
```bash
./make_emulator_german.sh
```

**Windows:**
```powershell
.\make_emulator_german.ps1
```

Das Skript findet den laufenden Emulator automatisch. Laufen mehrere Emulatoren gleichzeitig, kann die Seriennummer explizit angegeben werden, z. B. `./make_emulator_german.sh emulator-5556` bzw. `.\make_emulator_german.ps1 -Serial emulator-5556` (Seriennummer mit `adb devices` herausfinden).

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

Für alle `.sh`-Skripte gilt, dass das Recht zur Ausführung erteilt werden muss (`chmod +x <skript>`) — im Repository ist das bereits gesetzt. Siehe die Kommentare in den Skripten für weitere Details.

Für jedes `.sh`-Skript existiert ein gleichwertiges `.ps1`-Gegenstück für Windows (Ausnahme: `mac_make_rootca_trusted.sh` und `windows_make_rootca_trusted.ps1`, da das Vertrauen von Zertifikaten pro Betriebssystem grundlegend unterschiedlich funktioniert). Wer eines der Skripte ändert, sollte das Gegenstück auf der anderen Plattform entsprechend nachziehen.
