## Apache Guacamole

Apache Guacamole ist ein browserbasierter Remote-Desktop-Gateway. Der Zugriff auf entfernte Systeme erfolgt direkt über einen Webbrowser, ohne dass auf dem Client ein zusätzlicher RDP-, VNC- oder SSH-Client installiert werden muss.

In diesem Setup dient Guacamole als zentraler Einstiegspunkt für den Zugriff auf mehrere Ubuntu-Systeme mit XRDP.

Die Verbindung erfolgt nach folgendem Prinzip:

```text
Webbrowser
    |
Apache Guacamole
    |
guacd
    |
RDP / XRDP
    |
Ubuntu-System
```

Für jeden Kursteilnehmer ist ein eigener Guacamole-Benutzer definiert. Nach der Anmeldung wird dem Benutzer das für ihn vorgesehene Zielsystem angezeigt.

Beispiel:

```text
user1 --> ws01 --> 10.10.1.11
user2 --> ws02 --> 10.10.1.12
user3 --> ws03 --> 10.10.1.13
user4 --> ws04 --> 10.10.1.14
user5 --> ws05 --> 10.10.1.15
```

Die eigentliche RDP-Anmeldung auf den Ubuntu-Systemen erfolgt über XRDP. Die dafür benötigten Zugangsdaten sind bereits in der [Guacamole-Konfiguration](config/user-mapping.xml) hinterlegt.

### Guacamole starten

Die Container können mit Docker Compose gestartet werden:

    docker-compose up -d

Der Status der Container lässt sich anschliessend prüfen:

    docker compose ps

Der Zugriff auf Guacamole erfolgt danach über den Browser:

    http://<IP-Adresse-des-Guacamole-Servers>:8080/guacamole/

Für die Anmeldung werden die vorkonfigurierten Guacamole-Benutzer verwendet, beispielsweise:

    Benutzer: user1
    Passwort: insecure

Nach erfolgreicher Anmeldung kann die zugewiesene Verbindung geöffnet werden. Guacamole stellt anschliessend die RDP-Verbindung zum entsprechenden Ubuntu-System her.
