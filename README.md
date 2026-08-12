# Taptrap Deployment Guide

Dies ist der offizielle Deployment Guide von Taptrap. Er dient als Grundlage und Ergänzung dafür, wie man Taptrap auf einem Pixel-6a-Emulator simulieren kann, um Zugriffsrechte zu erhalten, ohne dass der Benutzer etwas von der Prozedur mitbekommt. Zusätzlich werden Skripte bereitgestellt, welche die Analysen ermöglichen. Dieses Repository soll somit als Ergänzung zur Hausarbeit dienen, sodass interessierten Lesern eine leichtere Nachbildung der Experimente möglich ist.

Diese Anleitung richtet sich auch an Leser ohne viel Vorerfahrung mit Kommandozeile, Docker oder Android-Entwicklung — jeder Schritt wird kurz erklärt, bevor der eigentliche Befehl kommt. Die Anleitung deckt **macOS** (Intel & Apple Silicon), **Ubuntu/Debian** und **Fedora/RHEL** über `setup.sh` sowie **Windows** über `setup.ps1` ab. Andere Linux-Distributionen funktionieren beim Webserver/Emulator-Teil in der Regel ebenfalls, beim Schritt `trust` (Root-Zertifikat vertrauen) muss dort aber manuell nachgeholfen werden.

## Was passiert hier eigentlich?

Für die Demo werden zwei Dinge gebraucht:

1. Ein **Android-Emulator**, auf dem die präparierte App installiert wird.
2. Ein **eigener Webserver mit HTTPS**, der die Webseite bereitstellt, die als Vorwand für den Angriff dient. Android verweigert ohne gültiges HTTPS-Zertifikat den Zugriff auf die Seite, deshalb muss ein eigenes Zertifikat erzeugt und sowohl dem eigenen Rechner als auch dem Emulator "beigebracht" werden, dass es vertrauenswürdig ist.

Die folgenden Schritte bauen aufeinander auf und sollten in dieser Reihenfolge ausgeführt werden.

## Voraussetzungen

| Werkzeug | macOS | Linux | Windows |
|---|---|---|---|
| Android Studio (inkl. SDK, `adb`) | [Download](https://developer.android.com/studio) | [Download](https://developer.android.com/studio) | [Download](https://developer.android.com/studio) |
| Docker | [Docker Desktop](https://www.docker.com/products/docker-desktop/) | [Docker Engine](https://docs.docker.com/engine/install/) (Ubuntu/Debian, Fedora/RHEL, …) oder Docker Desktop | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (WSL2-Backend empfohlen) |
| OpenSSL | bereits vorinstalliert | bereits vorinstalliert (sonst Paket `openssl` der Distribution) | über [Git for Windows](https://git-scm.com/download/win) (bringt `openssl.exe` mit) oder `winget install ShiningLight.OpenSSL` |
| Terminal | Terminal.app / iTerm | Terminal der Distribution (z. B. GNOME Terminal, Konsole) | PowerShell (vorinstalliert) |

Stellt sicher, dass `adb` im `PATH` liegt (Android Studio → Settings → SDK-Verzeichnis, Unterordner `platform-tools`). Ob es funktioniert, lässt sich mit `adb --version` (macOS/Linux) bzw. `adb.exe --version` (Windows) prüfen.

**Windows + adb:** Android Studio fügt den `platform-tools`-Ordner **nicht automatisch** zum `PATH` hinzu. SDK-Pfad in Android Studio nachschauen (Settings → Languages & Frameworks → Android SDK, meist `C:\Users\<Name>\AppData\Local\Android\Sdk`) und dann `platform-tools` zum `PATH` hinzufügen:

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Users\<Name>\AppData\Local\Android\Sdk\platform-tools", "User")
```

Danach alle offenen Terminals neu starten (PATH-Änderungen gelten nicht rückwirkend) und mit `adb --version` prüfen.

**Windows + OpenSSL:** Bei der Installation von Git for Windows bei "Adjusting your PATH environment" die Option **"Git from the command line and also from 3rd-party software"** wählen (nicht die minimale "Git Bash only"-Option). Damit landet `openssl.exe` direkt im System-`PATH` und ist auch in einer normalen PowerShell nutzbar — es muss dafür **nicht** zusätzlich auf Git Bash gewechselt werden. Alle Schritte (inkl. `trust`) laufen dann durchgängig über `setup.ps1` in PowerShell.

Wurde die PATH-Option beim Installieren übersehen, hilft ein erneuter Durchlauf des Git-Installers (Option nachträglich aktivieren) statt manuell am `PATH` herumzueditieren.

### Hinweis für Windows: Skripte ausführen

Windows blockiert das Ausführen von `.ps1`-Dateien standardmäßig. Einmalig in einer **normalen** PowerShell (nicht als Administrator) ausführen:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Skripte, die Änderungen am System vornehmen (Zertifikatsspeicher), müssen zusätzlich **als Administrator** ausgeführt werden — das ist beim jeweiligen Schritt unten vermerkt.

Meldet PowerShell trotzdem, dass das Skript nicht "digitally signed" sei (typisch auf verwalteten Hochschul-/Firmenrechnern, wo die Policy per Gruppenrichtlinie erzwungen wird und sich mit obigem Befehl nicht überschreiben lässt), jeden Aufruf stattdessen so voranstellen — das setzt die Policy nur für diesen einen Prozess, ohne etwas dauerhaft zu ändern:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 certs
powershell -ExecutionPolicy Bypass -File .\setup.ps1 trust
```

(usw. für jeden Schritt). Ob eine Gruppenrichtlinie greift, zeigt `Get-ExecutionPolicy -List` — stehen `MachinePolicy`/`UserPolicy` auf etwas anderem als `Undefined`, ist das der Grund.

**Wichtig:** Auf Windows sollten alle Schritte über `setup.ps1` in PowerShell laufen, nicht über `setup.sh` in Git Bash — der `trust`-Schritt in `setup.sh` erkennt nur macOS und Linux (`uname -s`) und bricht unter Git Bash mit "Unbekanntes Betriebssystem" ab. Mit der obigen OpenSSL-Installation ist Git Bash für nichts mehr nötig.

Alle Schritte unten werden über eines von zwei Setup-Skripten ausgeführt: `setup.sh` für macOS/Linux (Terminal) und `setup.ps1` für Windows (PowerShell). Windows-Skripte startet man mit vorangestelltem `.\`, z. B. `.\setup.ps1`.

Beide Skripte lassen sich auf drei Arten nutzen:

- **Interaktiv:** einfach ohne Argumente aufrufen (`./setup.sh` bzw. `.\setup.ps1`) — es erscheint ein Menü, aus dem der gewünschte Schritt per Nummer oder Name ausgewählt wird.
- **Direkt:** mit dem Schrittnamen als Argument, z. B. `./setup.sh certs` bzw. `.\setup.ps1 certs`. So lassen sich Schritte auch aus eigenen Skripten heraus automatisieren. Manche Schritte akzeptieren zusätzliche Argumente, z. B. `./setup.sh transparency hide` oder `./setup.sh webapp remote`.
- **Hilfe:** `./setup.sh --help` bzw. `.\setup.ps1 --help` (auch `-h`/`help`) zeigt alle Schritte samt ihrer möglichen Argumente und Beispielaufrufen an, ohne dass dafür die README durchsucht werden muss.

Die verfügbaren Schritte sind `certs`, `trust`, `build`, `run`, `load-ca` und `all` (führt `certs`, `trust` und `build` nacheinander aus) — sie entsprechen den Schritten 2, 3, 4 und 6 weiter unten. Dazu kommen die optionalen Zusatzschritte `wipe-data` (Schritt 5), `check-permissions` (Schritt 8), `transparency` (Schritt 9) und `webapp` (Schritt 10), die es aktuell nur unter `setup.sh` (macOS/Linux) gibt. Schritt 7 "App testen" erfolgt manuell in Android Studio und hat keinen eigenen Setup-Schritt.

## Schritt-für-Schritt-Anleitung

### 1. Android Studio & Emulator einrichten

Als Emulator sollte ein **Pixel 6a** mit **Android 15** (API Level 35, "VanillaIceCream") und **Google APIs** als Services gewählt werden.

Für die Einrichtung von Android Studio sowie den benötigten `sdkmanager` und `cmdline-tools` sei auf das Referenz-Repository [beerphilipp/taptrap](https://github.com/beerphilipp/taptrap) verwiesen. Startet den Emulator, bevor ihr mit den emulatorbezogenen Schritten (ab Schritt 5) fortfahrt.

### 2. TLS-Zertifikate erzeugen

*Warum?* Damit der Emulator die eigene Webseite über HTTPS ohne Warnung/Fehler laden kann, braucht der Webserver ein Zertifikat. Da es keine öffentliche Domain gibt, wird eine eigene, kleine Zertifizierungsstelle ("Root CA") erstellt, die anschließend ein Server-Zertifikat für `localhost` signiert.

Die Dateien landen direkt im Ordner `certs/` und müssen **einmalig** erzeugt werden. Sie sind bewusst in `.gitignore` eingetragen und werden nicht ins Repository übernommen.

**macOS/Linux:**
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

**macOS/Linux** (fragt nach einem Passwort — macOS: Login-Passwort für den Schlüsselbund, Linux: `sudo`-Passwort):
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

Docker (Docker Desktop bzw. unter Linux der Docker-Daemon) muss vorher gestartet sein.

**macOS/Linux:**
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

### 5. (Optional) Emulator auf Werkszustand zurücksetzen

*Warum?* Für einen wiederholt sauberen Demo-Durchlauf (keine alte App-Installation, kein alter Zertifikats- oder Geräteadmin-Status) lässt sich der Emulator per Skript zurücksetzen, statt das in Android Studio manuell über "Wipe Data" zu machen.

**macOS/Linux:**
```bash
./setup.sh wipe-data
```

Das Skript fragt zur Sicherheit nach Bestätigung (mit `./setup.sh wipe-data yes` überspringen), stoppt den laufenden Emulator und startet ihn mit `-wipe-data` neu. Der Neustart läuft im Hintergrund; mit `adb wait-for-device` oder im Android-Studio-Fenster lässt sich der Bootvorgang abwarten. Danach müssen `load-ca` (Schritt 6) und die App-Installation (Schritt 7) erneut ausgeführt werden.

Dieser Schritt existiert aktuell nur unter `setup.sh` (macOS/Linux), nicht unter `setup.ps1`.

### 6. Root-Zertifikat auf den Emulator laden

*Warum?* Auch der Emulator selbst muss der Root CA vertrauen, sonst blockiert Android die HTTPS-Verbindung zur eigenen Webseite.

Emulator muss laufen, bevor dieser Schritt ausgeführt wird.

**macOS/Linux:**
```bash
./setup.sh load-ca
```

**Windows:**
```powershell
.\setup.ps1 load-ca
```

Das Skript versucht zuerst, das Zertifikat automatisch als systemweit vertrauenswürdige CA zu installieren (`adb root` + `adb remount`, Zertifikat nach `/system/etc/security/cacerts/` kopieren, Emulator neu starten). Das funktioniert nur auf einem **Google-APIs**-Emulator-Image (nicht Play Store, siehe Schritt 1) — auf "production"/Play-Store-Images verweigert `adbd` den Root-Zugriff.

Klappt die automatische Installation nicht, fällt das Skript automatisch auf den manuellen Weg zurück: Es kopiert das Zertifikat in den Download-Ordner des Emulators und zeigt an, wo es im Emulator manuell importiert werden muss: **Einstellungen → Suchleiste → "Zertifikate installieren" → Datei aus dem Download-Ordner wählen.**

Wird der Emulator zurückgesetzt (Schritt 5 oder manuell über "Wipe Data"), geht der Import verloren und dieser Schritt muss wiederholt werden.

### 7. App testen

Sobald der Webserver läuft (Schritt 4) und der Emulator dem Zertifikat vertraut (Schritt 6), kann die App aus Android Studio auf den Emulator installiert und die Demo durchlaufen werden. Die Ziel-URL ist in

```
KillTheBugs/app/src/main/res/values/strings.xml
```

als `webapp`-String hinterlegt und lässt sich per Skript umschalten (siehe Schritt 10 unten) — je nachdem, ob der eigene lokale Webserver aus Schritt 4 oder die öffentliche Demo-Seite verwendet werden soll.

### 8. (Optional) Erteilte Berechtigungen prüfen

*Warum?* Das Spiel selbst zeigt absichtlich nicht an, ob ein Exploit-Versuch tatsächlich erfolgreich war (siehe die Logcat-Hinweise in [`LevelActivity.kt`](KillTheBugs/app/src/main/java/com/taptrap/userstudy/killthebugs/LevelActivity.kt)). Dieser Schritt fragt stattdessen direkt beim Android-Berechtigungssystem nach, was die App tatsächlich erreicht hat.

**macOS/Linux:**
```bash
./setup.sh check-permissions
```

Das Skript zeigt zwei Dinge an:

- Die Laufzeitberechtigungen (`CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`) aus `adb shell dumpsys package com.android.chrome`, relevant für Level 1 und 2. Wichtig: Die Custom-Tab-Exploits laufen innerhalb von Chrome, deshalb landen erteilte Berechtigungen bei **Chrome** (`com.android.chrome`) und nicht bei der KillTheBugs-App selbst — ein Check gegen das KillTheBugs-Paket würde hier immer "nicht erteilt" zeigen, selbst nach einem erfolgreichen Exploit.
- Ob die KillTheBugs-App (`com.taptrap.userstudy.killthebugs`) als Geräteadministrator aktiv ist (`adb shell dumpsys device_policy`), relevant für Level 3. Das läuft direkt über die App, hier ist der Check gegen das KillTheBugs-Paket korrekt.

Dieser Schritt existiert aktuell nur unter `setup.sh` (macOS/Linux), nicht unter `setup.ps1`.

### 9. (Optional) Deckkraft der Tarn-Animation umschalten

*Warum?* Während des Exploits (3. Punkt in jedem Level) wird der echte System-Dialog (Custom-Tab-Berechtigungsabfrage bzw. "Als Geräteadministrator aktivieren") über eine Android-Animation stark gezoomt eingeblendet und mit einem festen Alpha-Wert überlagert, damit er wie ein Teil des Spiels aussieht ([`LevelActivity.kt`](KillTheBugs/app/src/main/java/com/taptrap/userstudy/killthebugs/LevelActivity.kt), `exploitCustomTab`/`exploitDeviceManager`, sowie die `res/anim/fade_in_*`-Dateien). Für Vorführungen ist es hilfreich, kurz sichtbar zu machen, was tatsächlich im Hintergrund passiert, und danach wieder auf den unauffälligen Wert für den echten Angriff zurückzuschalten.

**macOS/Linux:**
```bash
./setup.sh transparency show   # mittel sichtbar (alpha=0.5) – für Vorführungen, Käfer bleiben erkennbar
./setup.sh transparency hide   # für das Auge quasi unsichtbar (alpha=0.02) – wie im echten Angriff
./setup.sh transparency        # zeigt die aktuell gesetzten Werte an
```

Das Skript patcht die `android:fromAlpha`/`android:toAlpha`-Werte in allen sechs betroffenen `res/anim/fade_in_*.xml`-Dateien. Nach dem Umschalten muss die KillTheBugs-App neu gebaut und auf dem Emulator installiert werden (Android Studio: **Run**, oder `cd KillTheBugs && ./gradlew installDebug`), damit die Änderung sichtbar wird — das Setup-Skript baut die Android-App selbst nicht.

Dieser Schritt existiert aktuell nur unter `setup.sh` (macOS/Linux), nicht unter `setup.ps1`.

### 10. (Optional) Zwischen lokaler und öffentlicher Ziel-URL wechseln

*Warum?* Die App braucht für die eigene, lokale Webseite aus Schritt 4 eine andere `webapp`-URL (`https://10.0.2.2:5002`) als für die öffentliche Demo-Seite (`https://killthebugs.taptrap.click/`). Praktisch für einen sauberen, wiederholbaren lokalen Testlauf ohne den öffentlichen Server — und zum schnellen Zurückwechseln, sobald man mit den Ergebnissen zufrieden ist.

**macOS/Linux:**
```bash
./setup.sh webapp local    # eigener Webserver aus Schritt 4 (https://10.0.2.2:5002)
./setup.sh webapp remote   # öffentliche Demo-Seite (https://killthebugs.taptrap.click/)
./setup.sh webapp          # zeigt die aktuell gesetzte URL an
```

Das Skript patcht direkt den `webapp`-String in `KillTheBugs/app/src/main/res/values/strings.xml`. Für `local` muss zusätzlich der Webserver laufen (Schritt 4) und der Emulator der Root-CA vertrauen (Schritt 6). Wie bei den anderen App-Konfigurationsschritten muss die App danach neu gebaut und installiert werden, damit die Änderung wirksam wird.

Dieser Schritt existiert aktuell nur unter `setup.sh` (macOS/Linux), nicht unter `setup.ps1`.

## Fehlerbehebung

- **"docker: command not found" / "Cannot connect to the Docker daemon"** — Docker Desktop ist nicht installiert oder nicht gestartet.
- **`./setup.sh run` schlägt mit "Permission denied" beim Lesen von `server.crt`/`server.key` fehl, obwohl Docker läuft und die Gruppenmitgliedschaft stimmt (z. B. Fedora/RHEL)** — SELinux blockiert den Zugriff des Containers auf die gemounteten Dateien. Das Skript erkennt aktives SELinux automatisch (`getenforce`) und hängt in diesem Fall `,z` an die Bind-Mounts an; betrifft nur `setup.sh`, nicht `setup.ps1` (Windows kennt kein SELinux).
- **PowerShell verweigert die Ausführung eines `.ps1`-Skripts / meldet "not digitally signed"** — siehe [Hinweis für Windows](#hinweis-für-windows-skripte-ausführen) oben, insbesondere den `-ExecutionPolicy Bypass`-Fallback für per Gruppenrichtlinie verwaltete Rechner.
- **`certutil` schlägt ohne klare Fehlermeldung fehl** — PowerShell wurde nicht als Administrator gestartet.
- **"'openssl' wurde nicht gefunden" unter Windows** — Git for Windows wurde ohne die PATH-Option installiert, siehe [Hinweis Windows + OpenSSL](#voraussetzungen) oben.
- **`./setup.sh trust` meldet "Unbekanntes Betriebssystem" in Git Bash unter Windows** — `setup.sh` unterstützt den `trust`-Schritt nur für macOS/Linux. Unter Windows stattdessen `.\setup.ps1 trust` (als Administrator) verwenden.
- **Zertifikatsfehler im Emulator-Browser trotz Import** — Emulator wurde zwischenzeitlich zurückgesetzt ("Wipe Data" bzw. Schritt 5); Schritt 6 (`load-ca`) erneut ausführen.
- **`load-ca` faellt immer auf die manuelle Installation zurueck** — Emulator ist ein Play-Store-Image statt eines Google-APIs-Images; `adbd` verweigert dort grundsaetzlich Root-Zugriff (siehe Schritt 1).
- **`adb` erkennt keinen Emulator** — Emulator ist nicht gestartet, oder `adb` liegt nicht im `PATH`.
- **"'adb' wurde nicht gefunden" unter Windows (z. B. bei `load-ca`)** — Android Studio fügt `platform-tools` nicht automatisch zum `PATH` hinzu, siehe [Hinweis Windows + adb](#voraussetzungen) oben.

## Entwicklung

Die gesamte Setup-Logik steckt in genau zwei Dateien: `setup.sh` (macOS/Linux) und `setup.ps1` (Windows). Beide bilden dieselben sechs Kern-Schritte (`certs`, `trust`, `build`, `run`, `load-ca`, `all`) als Funktionen ab, die entweder über das interaktive Menü oder direkt per Argument aufgerufen werden. Wer einen dieser Schritte ändert oder einen neuen hinzufügt, sollte das jeweils in beiden Dateien tun, damit macOS/Linux und Windows im Funktionsumfang gleichauf bleiben. `setup.sh` bietet zusätzlich die Schritte `wipe-data`, `check-permissions`, `transparency` und `webapp` (siehe Abschnitte 5, 8, 9 und 10 oben), die bewusst nur für macOS/Linux existieren.

`setup.sh` benötigt das Ausführungsrecht (`chmod +x setup.sh`) — im Repository ist das bereits gesetzt.
