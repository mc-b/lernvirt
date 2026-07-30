# Security-Empfehlungen

Dieses Dokument beschreibt sicherheitsrelevante Anpassungen für Passwörter, SSH-Keys sowie die Verarbeitung von `user-data`- und Cloud-Init-Dateien.

## Keine unsicheren Standardpasswörter verwenden

Ein fest hinterlegtes und öffentlich bekanntes Passwort wie:

    echo "ubuntu:insecure" | chpasswd

soll nicht verwendet werden.

Stattdessen soll für jede Installation ein zufälliges Passwort erzeugt werden:

    echo "ubuntu:$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 16)" | chpasswd

Dadurch wird bei jedem Durchlauf ein neues, zufälliges Passwort mit 16 Zeichen gesetzt.

> Hinweis: Falls der Benutzer ausschliesslich per SSH-Key authentifiziert wird, sollte die Passwortanmeldung zusätzlich deaktiviert werden.

Beispiel für Cloud-Init:

    ssh_pwauth: false

## Unsicheren SSH-Key ersetzen

Der öffentliche SSH-Key mit dem Kommentar:

    insecure@lerncloud

ist ein unsicherer Standard-Key und muss aus allen folgenden Dateien entfernt beziehungsweise ersetzt werden:

- `user-data`-Dateien
- Cloud-Init-Dateien
- Templates und Beispiele
- PXE-Installationsdateien
- automatisch generierte temporäre Cloud-Init-Konfigurationen

Zur Suche im Repository kann folgender Befehl verwendet werden:

    grep -RIn --exclude-dir=.git 'insecure@lerncloud' .

Der gefundene Key muss durch einen eigenen öffentlichen SSH-Key ersetzt werden, beispielsweise:

    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mein-name@meine-firma

Es soll nur der öffentliche Key verteilt werden. Der private SSH-Key darf nie im Repository, in Images, in Cloud-Init-Dateien oder in Installationsskripten gespeichert werden.

## Eigenen SSH-Key erzeugen

Falls noch kein eigener SSH-Key vorhanden ist, kann ein Ed25519-Key erzeugt werden:

    ssh-keygen -t ed25519 -a 100 -C "admin@example"

Der öffentliche Key befindet sich standardmässig in:

    ~/.ssh/id_ed25519.pub

## Anpassung in `pxe/install-pxe.sh`

In der Datei:

    pxe/install-pxe.sh

muss die bestehende Logik geändert werden.

Aktuell ist die Ersetzungszeile deaktiviert und die Zeile zum zusätzlichen Einfügen des Keys aktiv:

    # sed -i "s|ssh-rsa .* insecure@lerncloud|${pub_key}|" "$temp_userdata"
    sed -i "\|ssh-rsa .* insecure@lerncloud|a\\      - ${pub_key}" "$temp_userdata"

Die erste Zeile muss aktiviert und die zweite Zeile deaktiviert werden:

    sed -i "s|ssh-rsa .* insecure@lerncloud|${pub_key}|" "$temp_userdata"
    # sed -i "\|ssh-rsa .* insecure@lerncloud|a\\      - ${pub_key}" "$temp_userdata"

Damit wird der unsichere Standard-Key ersetzt, statt den neuen Key lediglich zusätzlich einzufügen.


