Taptrap Deployment Guide

Es ist der offizielle Deployment Guide von Taptrap auf MacOS. Es dient als Grundlage und Ergänzung dafür wie man Taptrap auf einem Pixel 6a Emulator simulieren kann um Zugriffsrechte zu erhalten, ohne dass der Benutzer etwas von der Prozedur mitkriegt. Zusätzlich sollen Skripte bereitgestellt werden, welche die Analyzen bereitstellen. Dieser soll somit zusätzlich als Ergänzung zu der Hausarbeit dienen, sodass bei womöglichen Interessenten ein leichtere Nachbildung der Experimente möglich ist.



# Entwicklung

Hier einige kleine Informationen für Entwickler. Bisher wurde die Entwicklung auf MacOS angepasst. Weitere Einstellungen für Linux / Windows sind willkommen.

## Skripte

Für alle Skripte gilt, dass das Recht für die Ausführung erteilt werden muss. Siehe Kommentare in den Skripten für weitere Informationen.

## Web-Server

Der eigene Web-Server funktioniert nur einwandfrei mit zusätzlicher aufwendiger Konfiguration von HTTPS. Ohne HTTPS ist es nicht möglich ohne weiteres das Demo von Taptrap durchlaufen zu lassen ohne Unterbrechungen. Der Zugang wird einfach verweigert. Die folgende Konfiguration wird empfohlen, wenn man oftmals den Emulator von erstellten Daten befreit um die Dmeos nochmal sauber durchzulaufen:

```xml
<resources>
    <string name="app_name">ToeteDieKaefer</string>
    <string name="webapp">https://killthebugs.taptrap.click/</string>
    <string name="pivotY_Pixel6a">57.75%</string>
    <string name="pivotY_Edge20">56%</string>
</resources>
```

Die Datei befindet sich in `/res/values/strings.xml`. Sobald man zufrieden ist so kann man zurück zu `https://10.0.2.2:5002` gewechselt werden.

### Webserver starten

Für den Webserver muss Docker installiert werden. Für die Erstellung des Images muss `build_server.sh` ausgeführt werden. 

### HTTPS Konfiguration

Das Skript für die Generierung der Zertifikate und das rüberkopieren ist in Skripten bereitgestellt worden. Einmal unter `certs` befindet sich die Datei für die Generierung der Zertifikate und die Erstellung der Zertifizierungskette.

Zusätzlich gibt es das Skript `mac_make_rootca_trusted.sh` welches ausdrücklich für MacOS das Zertifikat vertrauenswürdig macht. So kann die Webseite auf dem eigenen Rechner getestet und mit interagiert werden.

Das Skript `load_rootca_to_emulator.sh` erwartet einen laufenden Emulator auf den das rootCA geladen wird. Anschließend wird eine Meldung angezeigt wo man in der Emulator Oberfläche navigieren muss, die Datei importieren kann und somit HTTPS für die Webseite funktioniert. Wird der Emulator befreit, so muss die ganze Prozedur erneut gemacht werden, so wird für Testzwecke die vorgegebene Webseite empfohlen, bis man mit den Ergebnissen des deutschen Layouts zufrieden ist.

## Android Studio

Als Emulator sollte Pixel 6a gewählt werden und ein Emulator mit der Android version 15 und API Version 35 "VanillaIceCream" mit Google APIs als Services.

Wählt man Google Play Store als Service, so kann man das Umstellen der Systemsprache nicht mit adb automatisieren. Ansonsten ist es nicht weiter von Bedeutung.

Für die Konfiguration von Android Studio und die benötigten sdkmanager und cmdline-tools sei auf das Referenz-Repository [https://github.com/beerphilipp/taptrap](https://github.com/beerphilipp/taptrap) verwiesen.

