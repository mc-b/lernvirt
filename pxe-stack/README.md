# lernvirt PXE Stack

`pxe-stack` stellt eine PXE-Basis für lernvirt bereit. Ein PXE-Server liefert GRUB, Ubuntu-Installationsmedien und die gewünschte Lernumgebung aus. Welche Umgebung ein Client erhält, wird nicht in `grub.cfg` fest programmiert, sondern über **Stacks** in `/srv/tftp/config/rack.conf` ausgewählt.

Die PXE-Basis verwendet die bestehende lernvirt-PXE-Logik: `dnsmasq` arbeitet als Proxy-DHCP/TFTP, nginx liefert die HTTP-Dateien auf Port 80 aus, x86_64 und ARM64 werden unterstützt und ein vorhandenes `/boot/lernvirt-installed` führt standardmässig zum lokalen Boot.

## Installation mit cloud-init

Für eine neue Installation reicht in cloud-init:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -']
```

Weitere Beispiele:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna-full BOOT_TOOLS=0 bash -']
```

Mit vorgegebenem SSH Public Key:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna SSH_PUBLIC_KEY_URL=https://raw.githubusercontent.com/mc-b/lerncloud/main/ssh/lerncloud.pub bash -']
```

Wichtige Variablen beim ersten Setup:

| Variable | Default | Bedeutung |
|---|---|---|
| `STACK` | `ubuntu` | Default-Stack für alle Clients |
| `VARIANT` | leer | optionale Stack-spezifische Variante |
| `BOOT_TOOLS` | `1` | Alpine/BusyBox im GRUB-Menü ein-/ausschalten |
| `PREPARE_ASSETS` | `1` | benötigte Images sofort herunterladen/vorbereiten |
| `SSH_PUBLIC_KEY_URL` | leer | optionaler SSH Public Key |

**Wichtig:** `STACK` und `VARIANT` erzeugen nur beim ersten Setup die initiale `HOSTS`-Regel. Existiert `/srv/tftp/config/rack.conf` bereits, bleibt diese Konfiguration bei einem erneuten Lauf von `install-pxe.sh` erhalten. Bestehende Installationen werden über `rack.conf` konfiguriert.

## Was ist ein Stack?

Ein Stack beschreibt, **was ein PXE-Client booten oder installieren soll**. Technisch ist ein Stack eine GRUB-Datei:

```text
/srv/tftp/grub/stacks/<stack>.cfg
```

Die zentrale `grub.cfg` kennt keine feste Liste von Umgebungen. Sie ermittelt anhand der MAC-Adresse den Stack und lädt danach dynamisch:

```grub
source (tftp,${tftp_server})/grub/stacks/${stack}.cfg
```

Die mitgelieferten Basis-Stacks sind:

| Stack | Funktion |
|---|---|
| `ubuntu` | Ubuntu Autoinstall mit `user-data` |
| `cna` | Ubuntu Autoinstall mit `user-data-cna` |
| `cna-full` | Ubuntu Autoinstall mit `user-data-cna-full` |
| `platen` | Ubuntu Autoinstall mit `user-data-platen` |
| `reset` | Ubuntu Autoinstall mit `user-data-reset`; entfernt den Installationsmarker, aktiviert Wake-on-LAN und fährt den Rechner nach dem Reset herunter |

Die Ubuntu-basierten Stacks verwenden gemeinsam `_ubuntu-install.cfg`. Dadurch sind Kernel-, Initrd- und ISO-Parameter nur einmal definiert.

Ein Stack kann zusätzlich ein benötigtes Asset deklarieren:

```text
# PXE-ASSET: ubuntu
```

`pxe-prepare` ruft dafür automatisch auf:

```text
/srv/tftp/bin/prepare-ubuntu
```

Das gleiche Schema kann für neue Stacks verwendet werden.

## Bestehende Installation konfigurieren

Die zentrale Konfiguration liegt in:

```text
/srv/tftp/config/rack.conf
```

Der wichtigste Teil ist `HOSTS`:

```bash
HOSTS=(
    "MAC|STACK|VARIANT"
)
```

`*` gilt für alle Rechner. Regeln werden von oben nach unten ausgewertet; **die letzte passende Regel gewinnt**.

### Alle Rechner mit demselben Stack

```bash
HOSTS=(
    "*|cna|"
)
```

### Einzelnen Rechner überschreiben

```bash
HOSTS=(
    "*|cna|"
    "80:EE:73:EF:0D:E9|cna-full|"
)
```

Damit erhalten alle Rechner `cna`, nur die angegebene MAC erhält `cna-full`.

### Mehrere unterschiedliche Umgebungen

```bash
HOSTS=(
    "*|ubuntu|"
    "80:EE:73:EF:0D:E9|cna|"
    "80:EE:73:EF:03:B3|cna-full|"
    "80:EE:73:EF:01:81|platen|"
)
```

### Alle Rechner zurücksetzen

`reset` ist kein Sondermodus, sondern ein normaler Stack. Eine abschliessende `*`-Regel überschreibt deshalb alle vorherigen Zuweisungen:

```bash
HOSTS=(
    "*|cna|"
    "80:EE:73:EF:0D:E9|cna-full|"

    "*|reset|"
)
```

Nach dem Reset wird die letzte Zeile wieder entfernt und die Konfiguration neu gerendert.

### Änderungen aktivieren

Nach einer Änderung an `rack.conf`:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-show
```

Wenn ein neuer Stack, ein neues `user-data` oder neue Images benötigt werden:

```bash
sudo /srv/tftp/bin/pxe-prepare
```

Für reine Änderungen der Stack-Zuordnung ist kein Neustart von `dnsmasq` oder nginx nötig.

`pxe-show` zeigt die aktiven Hostregeln und die installierten Stacks:

```bash
sudo /srv/tftp/bin/pxe-show
```

## `/boot/lernvirt-installed`

Nach einer normalen lernvirt-Installation liegt auf dem Client:

```text
/boot/lernvirt-installed
```

Beim nächsten PXE-Boot sucht GRUB diesen Marker. Ist er vorhanden, wird standardmässig der lokale Boot gewählt.

Der Stack `reset` ignoriert den Marker absichtlich, damit eine Neuinstallation mit `user-data-reset` auch auf bereits installierten Rechnern gestartet wird.

## Alpine und BusyBox

Mit:

```bash
BOOT_TOOLS="1"
```

werden zusätzlich zwei reine RAM-Bootvarianten angeboten:

- Alpine Linux
- BusyBox/Alpine-Shell

Sie installieren nichts auf die lokale Platte und sind unabhängig vom ausgewählten Installations-Stack.

Assets neu laden:

```bash
sudo ALPINE_FORCE=1 /srv/tftp/bin/prepare-alpine
```

Boot-Tools abschalten: in `/srv/tftp/config/rack.conf`

```bash
BOOT_TOOLS="0"
```

anschliessend:

```bash
sudo /srv/tftp/bin/pxe-render
```

## Separate Add-ons

SUSE, OpenShift und HAProxy gehören bewusst **nicht** zur PXE-Basis. Die Basisinstallation verändert diese Dienste nicht.

### SUSE

Zuerst PXE-Basis installieren, danach:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | bash -
```

Die SUSE-ISO wird nicht automatisch vorausgesetzt. Sie kann anschliessend lokal oder per URL vorbereitet werden:

```bash
sudo SUSE_ISO=/pfad/SLE-15-SP6-Full-x86_64-GM-Media1.iso \
  /srv/tftp/bin/prepare-suse
```

oder:

```bash
sudo SUSE_ISO=https://server.example/suse.iso \
  /srv/tftp/bin/prepare-suse
```

Danach kann SUSE in `rack.conf` ausgewählt werden:

```bash
HOSTS=(
    "*|suse|"
)
```

Für AutoYaST enthält `VARIANT` den Dateinamen unter `/var/www/html/autoyast/`:

```bash
HOSTS=(
    "*|suse|"
    "80:EE:73:EF:01:81|suse|terra4.xml"
)
```

Danach:

```bash
sudo /srv/tftp/bin/pxe-render
```

### OpenShift

Add-on installieren:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | bash -
```

Dadurch werden der Stack und die RHCOS-Asset-Scripts installiert. Die OpenShift-Konfiguration liegt danach unter:

```text
/srv/tftp/config/openshift.conf
```

Diese Datei an das Rack anpassen, insbesondere Clustername, Domain, IPs, MAC-Adressen und Zielplatte.

RHCOS-Assets können erneut vorbereitet werden mit:

```bash
sudo /srv/tftp/bin/prepare-openshift
```

Für Ignition wird zusätzlich der Pull Secret benötigt, standardmässig:

```text
/etc/lernvirt/pull-secret.json
```

Danach:

```bash
sudo /srv/tftp/bin/prepare-openshift-ignition
```

Die Host-Zuordnung erfolgt wieder nur über `rack.conf`:

```bash
HOSTS=(
    "*|ubuntu|"
    "80:EE:73:EF:0D:E9|openshift|master"
    "80:EE:73:EF:03:B3|openshift|master"
    "80:EE:73:EF:01:81|openshift|master"
)
```

`VARIANT` wird beim OpenShift-Stack als Ignition-Rolle verwendet, z.B. `master` oder `worker`.

### HAProxy für OpenShift

HAProxy ist nochmals separat:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-haproxy.sh | bash -
```

Das Script liest `/srv/tftp/config/openshift.conf` und konfiguriert nur die OpenShift-Ports 6443 und 22623. nginx bleibt auf Port 80.

## Lösung erweitern

### Neuen Ubuntu-basierten Stack hinzufügen

Beispiel `kurs1` mit eigenem `user-data-kurs1`.

1. Autoinstall-Datei bereitstellen:

```bash
sudo cp user-data-kurs1 /var/www/html/autoinstall/user-data-kurs1
```

2. Stack erzeugen:

```bash
sudo tee /srv/tftp/grub/stacks/kurs1.cfg >/dev/null <<'STACK_EOF'
# PXE-ASSET: ubuntu
set userdata="user-data-kurs1"
source (tftp,${tftp_server})/grub/stacks/_ubuntu-install.cfg
STACK_EOF
```

3. Stack in `rack.conf` zuweisen:

```bash
HOSTS=(
    "*|kurs1|"
)
```

4. Rendern und Assets prüfen:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-prepare
```

Es ist keine Änderung an `grub.cfg`, `pxe-render` oder `pxe-prepare` nötig.

### Neuen Stack mit eigenen Images hinzufügen

Ein Stack kann einen eigenen Asset-Typ deklarieren, z.B.:

```text
/srv/tftp/grub/stacks/meinos.cfg
```

```grub
# PXE-ASSET: meinos

menuentry "Install MeinOS" {
    linux /linux/meinos/vmlinuz ip=dhcp
    initrd /linux/meinos/initrd
}
```

Dazu gehört ein ausführbares Script:

```text
/srv/tftp/bin/prepare-meinos
```

Dieses Script lädt bzw. erzeugt die benötigten Dateien unter `/srv/tftp` und/oder `/var/www/html`. Sobald der Stack in `HOSTS` aktiv ist, erkennt `pxe-prepare` die Zeile `# PXE-ASSET: meinos` und ruft automatisch `prepare-meinos` auf.

Danach genügt:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-prepare
```

### Erweiterung dauerhaft ins Repository aufnehmen

Für einen neuen Basis-Stack werden im Repository normalerweise nur diese Dateien ergänzt:

```text
pxe-stack/grub/stacks/<name>.cfg
pxe-stack/bin/prepare-<asset>       # nur wenn eigene Assets nötig sind
```

`install-pxe.sh` kopiert die Dateien aus `grub/stacks/` und `bin/` automatisch. Eine feste Stack-Liste muss nicht erweitert werden.

Für Funktionen, die nicht zur PXE-Basis gehören, sollte das gleiche Muster wie bei SUSE/OpenShift verwendet werden:

```text
pxe-stack/addons/<name>/...
pxe-stack/install-<name>.sh
```

Damit bleibt `install-pxe.sh` auf die gemeinsame PXE-Infrastruktur beschränkt.

## Wichtige Pfade

```text
/srv/tftp/config/rack.conf          zentrale Konfiguration
/srv/tftp/grub/grub.cfg             zentrales GRUB-Menü
/srv/tftp/grub/stacks/              installierte Stacks
/srv/tftp/grub/runtime.cfg          von pxe-render erzeugt
/srv/tftp/grub/hosts.cfg            von pxe-render erzeugte Hostregeln
/srv/tftp/bin/pxe-render            rack.conf -> GRUB-Konfiguration
/srv/tftp/bin/pxe-prepare           benötigte Stack-Assets vorbereiten
/srv/tftp/bin/pxe-show              aktuelle PXE-Konfiguration anzeigen
/var/www/html/autoinstall/          Ubuntu cloud-init/autoinstall-Dateien
/var/log/dnsmasq-pxe.log            PXE/DHCP-Log
/etc/lernvirt/lerncloud.pub         verwendeter SSH Public Key
```

Für einen normalen Wechsel der Lernumgebung sind damit nur drei Schritte nötig:

```bash
sudo vi /srv/tftp/config/rack.conf
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-prepare      # nur wenn neue Assets benötigt werden
```
