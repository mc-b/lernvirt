# lernvirt `pxe-stack`

Dynamische PXE-/GRUB-Struktur für lernvirt.

Das Paket ersetzt feste Verzweigungen wie `if ubuntu ... elif suse ...` durch eine einfache Regel:

```text
HOSTS -> stack -> grub/stacks/<stack>.cfg
```

Ein Stack ist nur eine GRUB-Datei. Neue Stacks benötigen keine Änderung an der zentralen `grub.cfg`.

## Zielbild

```text
/srv/tftp/
├── bin/
│   ├── pxe-render
│   ├── pxe-prepare
│   ├── pxe-show
│   ├── prepare-ubuntu
│   ├── prepare-alpine
│   ├── prepare-suse
│   ├── prepare-openshift
│   ├── prepare-openshift-ignition
│   └── prepare-ssh-key
├── config/
│   ├── rack.conf
│   ├── rack.conf.example
│   ├── openshift.conf
│   └── openshift.conf.example
├── grub/
│   ├── grub.cfg
│   ├── runtime.cfg              # generiert
│   ├── hosts.cfg                # generiert
│   ├── boot-tools.cfg
│   ├── x86_64-efi/...
│   └── stacks/
│       ├── ubuntu.cfg
│       ├── cna.cfg
│       ├── cna-full.cfg
│       ├── platen.cfg
│       ├── reset.cfg
│       ├── suse.cfg
│       ├── openshift.cfg
│       └── _ubuntu-install.cfg
└── linux/
    ├── ubuntu/...
    ├── alpine/...
    ├── suse/...
    └── openshift/...
```

HTTP-Inhalte liegen standardmässig unter `/var/www/html`. Der Provisionierungsserver lauscht standardmässig auf Port `8080`, damit `80/443` beispielsweise für OpenShift/HAProxy frei bleiben.

## Schnellstart

Für eine CNA-Umgebung:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -
```

Der Installer lädt anschliessend den kompletten `pxe-stack/`-Baum aus dem Repository-Archiv. Dadurch kennt `install-pxe.sh` keine feste Liste von Stack-Dateien oder Hilfsscripts: neue Dateien unter `grub/stacks/` und `bin/` werden automatisch übernommen.

Andere Beispiele:

```bash
# Normales Ubuntu
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=ubuntu bash -

# CNA Full
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna-full bash -

# Platen
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=platen bash -

# Gesamtes Rack zurücksetzen
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=reset bash -

# OpenShift / RHCOS
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=openshift VARIANT=master bash -

# SUSE mit lokal vorhandener ISO
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | \
  STACK=suse SUSE_ISO=/srv/iso/SLE-15-SP6-Full-x86_64-GM-Media1.iso bash -
```

Für einen vorhandenen PXE-Server kann die Asset-Vorbereitung übersprungen werden, wenn Kernel, initrd, Installationsmedien und benötigte Autoinstall-Dateien bereits vorhanden sind:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | \
  STACK=cna PREPARE_ASSETS=0 bash -
```


## SSH Public Key

Der Installer übernimmt die SSH-Key-Behandlung des bisherigen `pxe/`-Setups wieder. Ziel ist:

```text
/etc/lernvirt/lerncloud.pub
```

`prepare-ssh-key` arbeitet in dieser Reihenfolge:

1. vorhandenen `/etc/lernvirt/lerncloud.pub` verwenden,
2. einen passenden `.pub`-Key aus dem heruntergeladenen `lernvirt`-Repository übernehmen,
3. die `.pub`-Download-URL aus dem bisherigen `pxe/install-pxe.sh` übernehmen,
4. alternativ `SSH_PUBLIC_KEY_URL` verwenden.

Der Key wird zusätzlich unter folgendem Pfad über den Provisionierungsserver ausgeliefert:

```text
http://192.168.1.101:8080/ssh/lerncloud.pub
```

Die mitgelieferten `user-data`- und `user-data-reset`-Vorlagen übernehmen ihn in `~ubuntu/.ssh/authorized_keys`. OpenShift verwendet denselben lokalen Key über `SSH_KEY_FILE`.

Falls bewusst kein SSH-Key eingerichtet werden soll, kann die harte Prüfung deaktiviert werden:

```bash
SSH_KEY_REQUIRED=0
```

## Images und PXE-Artefakte

`PREPARE_ASSETS=1` ist Standard. Nach der Grundinstallation ruft `install-pxe.sh` automatisch `pxe-prepare` auf. Dadurch werden die Images/Boot-Artefakte für die effektiv aktiven Stacks geholt:

```text
Ubuntu     ISO herunterladen, casper/vmlinuz und casper/initrd extrahieren
Alpine     vmlinuz-lts, initramfs-lts und modloop-lts herunterladen
OpenShift  openshift-install laden und RHCOS Kernel, initramfs und rootfs ermitteln/laden
SUSE       angegebene SUSE_ISO übernehmen und Kernel/initrd + Installationsbaum bereitstellen
```

Für Ubuntu liegt das ISO danach beispielsweise unter:

```text
/var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso
```

und die TFTP-Dateien unter:

```text
/srv/tftp/linux/ubuntu/noble/amd64/vmlinuz
/srv/tftp/linux/ubuntu/noble/amd64/initrd
```

`PREPARE_ASSETS=0` ist nur für bereits vollständig vorbereitete PXE-Server gedacht.

## `/boot/lernvirt-installed`

Die bisherige Marker-Logik ist wieder enthalten. GRUB sucht lokal nach:

```text
/boot/lernvirt-installed
```

Dabei wird bewusst `localroot` verwendet:

```grub
search --no-floppy --file --set=localroot /boot/lernvirt-installed
```

Der TFTP-`root` bleibt dadurch unverändert. Ist der Marker vorhanden, ist `Boot installed system` der Default. Ohne Marker ist der Installations-Stack der Default.

Der Stack `reset` ist die Ausnahme: Er ignoriert einen vorhandenen Marker und startet weiterhin `user-data-reset`. Die mitgelieferten Basis- und Reset-Autoinstall-Dateien erzeugen den Marker am Ende der Installation mit:

```text
touch /target/boot/lernvirt-installed
```

Damit ergibt sich der gewünschte Zyklus:

```text
PXE Installation -> Marker vorhanden -> nächster PXE-Boot startet lokal
reset            -> Marker wird ignoriert -> Ubuntu Reset/WOL -> Marker neu gesetzt
```

## Cloud-init

Beispiel:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -']
```

Mit expliziten Netzwerkparametern:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna PXE_SERVER=192.168.1.101 PXE_INTERFACE=br0 PXE_NETWORK=192.168.1.0 PXE_NETMASK=255.255.255.0 bash -']
```

## Hostregeln

`/srv/tftp/config/rack.conf` enthält die Regeln.

Format:

```text
MAC|STACK|VARIANT
```

`*` bedeutet alle Rechner.

Die Regeln werden **von oben nach unten** ausgewertet. Die **letzte passende Regel gewinnt**.

### Alle Rechner gleich

Es ist keine MAC-Liste notwendig:

```bash
HOSTS=(
    "*|cna|"
)
```

Oder:

```bash
HOSTS=(
    "*|openshift|master"
)
```

### Unterschiedliche Umgebungen pro Host

```bash
HOSTS=(
    "*|ubuntu|"

    "80:EE:73:EF:0D:E9|openshift|master"
    "80:EE:73:EF:03:B3|openshift|master"
    "80:EE:73:EF:01:81|suse|"
)
```

Damit gilt:

```text
Default                  -> ubuntu
80:EE:73:EF:0D:E9        -> openshift / master
80:EE:73:EF:03:B3        -> openshift / master
80:EE:73:EF:01:81        -> suse
```

Nach einer Änderung:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-show
```

Es werden keine MAC-spezifischen Dateien mehr über TFTP gesucht. `pxe-render` erzeugt stattdessen eine einzige `grub/hosts.cfg`.

Damit entfällt auch das problematische Prüfen optionaler TFTP-Dateien mit `-e`.

`pxe-prepare` wertet dieselben Regeln aus und bereitet alle effektiv benötigten Assets vor. Regeln vor der letzten `*`-Regel sind für die Asset-Vorbereitung irrelevant; dadurch lädt ein abschliessendes `*|reset|` nicht unnötig vorherige OpenShift- oder SUSE-Assets.

## Reset

`reset` ist **kein Sonderzustand im Renderer**, sondern ein normaler Stack.

Der Stack installiert Ubuntu mit:

```text
user-data-reset
```

Das mitgelieferte Beispiel aktiviert Wake-on-LAN mittels `ethtool` bereits vor dem abschliessenden Ausschalten und installiert zusätzlich einen systemd-Dienst, der WOL bei späteren Boots erneut setzt. Firmware und NIC müssen Wake-on-LAN unterstützen und dürfen es nicht blockieren.

Wenn Reset immer für alle Rechner gelten soll, wird die Reset-Regel als letzte Regel eingetragen:

```bash
HOSTS=(
    "*|ubuntu|"

    "80:EE:73:EF:0D:E9|openshift|master"
    "80:EE:73:EF:03:B3|openshift|master"
    "80:EE:73:EF:01:81|suse|"

    "*|reset|"
)
```

Die letzte Regel gewinnt gegen alle MAC-Overrides.

Zur Rückkehr in die vorherige Umgebung wird nur die letzte Zeile entfernt oder auskommentiert und danach neu gerendert:

```bash
sudo /srv/tftp/bin/pxe-render
```

## Stacks

### Ubuntu

`ubuntu.cfg` setzt:

```text
userdata=user-data
```

und verwendet die gemeinsame Datei `_ubuntu-install.cfg`.

Standard:

```text
Ubuntu        24.04.4
Codename      noble
ISO           ubuntu-24.04.4-live-server-amd64.iso
```

Die Werte stehen in `rack.conf` und können geändert werden.

### CNA, CNA Full und Platen

Diese Stacks verwenden denselben Ubuntu-PXE-Boot und unterscheiden sich nur über die Autoinstall-Datei:

```text
cna       -> /autoinstall/user-data-cna
cna-full  -> /autoinstall/user-data-cna-full
platen    -> /autoinstall/user-data-platen
```

Vorhandene Autoinstall-Dateien unter `/var/www/html/autoinstall` werden vom Installer nicht überschrieben.

Das Paket enthält nur neutrale Beispiele für:

```text
/autoinstall/user-data
/autoinstall/user-data-reset
```

Die bestehenden lernvirt-spezifischen Dateien `user-data-cna`, `user-data-cna-full` und `user-data-platen` können unverändert weiterverwendet werden.

Wenn eine dieser Dateien beim Setup fehlt, versucht `install-pxe.sh`, sie aus dem bisherigen `mc-b/lernvirt`-Repository zu übernehmen. Bestehende lokale Dateien haben immer Vorrang.

### SUSE

Der SUSE-Stack lädt:

```text
TFTP /linux/suse/linux
TFTP /linux/suse/initrd
HTTP /linux/suse/current/
```

Die Installationsmedien werden mit folgendem Befehl vorbereitet:

```bash
sudo SUSE_ISO=/srv/iso/SLE-15-SP6-Full-x86_64-GM-Media1.iso \
  /srv/tftp/bin/prepare-suse
```

Auch eine HTTP-/HTTPS-URL kann verwendet werden:

```bash
sudo SUSE_ISO=https://server/path/openSUSE.iso \
  /srv/tftp/bin/prepare-suse
```

Bei SLES wird absichtlich keine ISO-Download-URL fest verdrahtet, weil das Installationsmedium von Subscription und Version abhängt.

Ohne `VARIANT` startet der Stack den interaktiven SUSE-Installer. Wird eine Variant angegeben, interpretiert der Stack sie als AutoYaST-Dateiname unter `/autoyast/`.

Beispiel:

```bash
HOSTS=(
    "*|suse|"
    "80:EE:73:EF:01:81|suse|terra4.xml"
)
```

Für `terra4` wird damit zusätzlich geladen:

```text
autoyast=http://192.168.1.101:8080/autoyast/terra4.xml
```

Die SUSE-Dokumentation verwendet für DHCP im Installer `netsetup=dhcp`; genau dieser Parameter ist im Stack hinterlegt.

### OpenShift

`openshift.cfg` installiert RHCOS per PXE.

Verwendet werden:

```text
coreos.live.rootfs_url
coreos.inst.install_dev
coreos.inst.ignition_url
```

`VARIANT` bestimmt die Ignition-Datei:

```text
master -> /openshift/master.ign
worker -> /openshift/worker.ign
```

Ohne Variant wird `master` verwendet.

Beispiel:

```bash
HOSTS=(
    "*|openshift|master"
    "80:EE:73:EF:01:81|openshift|worker"
)
```

RHCOS Assets vorbereiten:

```bash
sudo /srv/tftp/bin/prepare-openshift
```

Das Script verwendet standardmässig:

```text
OCP_CHANNEL=stable-4.20
```

und ermittelt die zugehörigen RHCOS-URLs über:

```bash
openshift-install coreos print-stream-json
```

Danach müssen die Ignition-Dateien erzeugt werden.

Standardpfade:

```text
/etc/lernvirt/pull-secret.json
/etc/lernvirt/lerncloud.pub
```

Dann:

```bash
sudo /srv/tftp/bin/prepare-openshift-ignition
```

Die OpenShift-Konfiguration liegt in:

```text
/srv/tftp/config/openshift.conf
```

und basiert auf:

```text
CLUSTER_NAME=ocp
BASE_DOMAIN=lernvirt.test
OCP_CHANNEL=stable-4.20
INSTALL_DISK=/dev/nvme0n1
```

Die Bootstrap-VM bleibt eine separate Infrastrukturkomponente. `prepare-openshift-ignition` erzeugt und publiziert auch `bootstrap.ign`.

## Alpine und BusyBox

Alpine und BusyBox sind keine Installations-Stacks.

Sie werden als optionale Boot-Varianten an jedes GRUB-Menü angehängt, wenn in `rack.conf` steht:

```bash
BOOT_TOOLS="1"
```

Die beiden Einträge verwenden dieselben Alpine-Netboot-Artefakte:

```text
Alpine Linux (RAM, keine Installation)
BusyBox Shell (Alpine initramfs, keine Installation)
```

BusyBox wird damit nicht mehr separat gepflegt. Der zweite Eintrag startet den Single-/Recovery-Modus des Alpine-initramfs.

Abschalten:

```bash
BOOT_TOOLS="0"
sudo /srv/tftp/bin/pxe-render
```

## Einen neuen Stack hinzufügen

Beispiel `rescue`:

```bash
sudo tee /srv/tftp/grub/stacks/rescue.cfg >/dev/null <<'EOF'
menuentry "Rescue" {
    linux /linux/rescue/vmlinuz ip=dhcp
    initrd /linux/rescue/initrd
}
EOF
```

Danach nur noch in `rack.conf` auswählen:

```bash
HOSTS=(
    "*|rescue|"
)
```

und rendern:

```bash
sudo /srv/tftp/bin/pxe-render
```

Die zentrale `grub.cfg` muss nicht geändert werden.

Wenn ein Stack Assets automatisch vorbereiten soll, kann die erste Zeile beispielsweise lauten:

```text
# PXE-ASSET: rescue
```

und ein ausführbares Script:

```text
/srv/tftp/bin/prepare-rescue
```

bereitgestellt werden. `install-pxe.sh` wertet diese Kennzeichnung generisch aus und enthält dafür keine feste Ubuntu/SUSE/OpenShift-Verzweigung.

## Generierte GRUB-Dateien

Aus:

```bash
HOSTS=(
    "*|ubuntu|"
    "80:EE:73:EF:0D:E9|openshift|master"
    "*|reset|"
)
```

wird sinngemäss:

```grub
set stack="ubuntu"
set variant=""

if [ "${net_default_mac}" = "80:ee:73:ef:0d:e9" ]; then
    set stack="openshift"
    set variant="master"
fi

set stack="reset"
set variant=""
```

Dadurch ist das Verhalten direkt nachvollziehbar und benötigt keine optionalen MAC-Dateien auf dem TFTP-Server.

## Wichtige Dateien

```text
/srv/tftp/config/rack.conf
```

Zentrale Rack-/Hostkonfiguration.

```text
/srv/tftp/grub/grub.cfg
```

Generischer GRUB-Einstiegspunkt.

```text
/srv/tftp/grub/runtime.cfg
```

Von `pxe-render` generierte Serverparameter.

```text
/srv/tftp/grub/hosts.cfg
```

Von `pxe-render` generierte Host-/Stackauswahl.

```text
/srv/tftp/grub/stacks/
```

Beliebig erweiterbare PXE-Stacks.

```text
/var/www/html/autoinstall/
```

Ubuntu Autoinstall-Daten.

## Installation und Dienste

`install-pxe.sh` richtet ein:

- `dnsmasq` als Proxy-DHCP und TFTP-Server
- GRUB UEFI x86_64 via `grub-mknetdir`
- `nginx` für Provisionierungsdaten, standardmässig Port `8080`
- `pxe-prepare` ermittelt die effektiv aktiven Stacks aus `HOSTS`
- Stack-Assets generisch anhand von `# PXE-ASSET: <name>` und `/srv/tftp/bin/prepare-<name>`
- identische Assets werden auch bei mehreren Stacks nur einmal vorbereitet
- Alpine-Netboot-Assets zusätzlich, wenn `BOOT_TOOLS=1`
- SSH Public Key nach `/etc/lernvirt/lerncloud.pub` und `/ssh/lerncloud.pub`
- lokale `/boot/lernvirt-installed`-Erkennung für den Default-Boot

Der vorhandene Router/DHCP bleibt für die IP-Adressvergabe zuständig.

### Secure Boot

Die mit `grub-mknetdir` erzeugte `core.efi` ist nicht als Secure-Boot-Chain ausgelegt. Auf PXE-Clients muss Secure Boot für diese Variante deaktiviert sein oder eine eigene signierte Boot-Chain eingesetzt werden.

## Konfigurierbare Variablen

Wichtige Variablen für `install-pxe.sh`:

| Variable | Default |
|---|---|
| `STACK` | `ubuntu` |
| `VARIANT` | leer |
| `PXE_SERVER` | `192.168.1.101` |
| `PXE_INTERFACE` | `br0` |
| `PXE_NETWORK` | `192.168.1.0` |
| `PXE_NETMASK` | `255.255.255.0` |
| `TFTP_ROOT` | `/srv/tftp` |
| `HTTP_ROOT` | `/var/www/html` |
| `PROVISION_HTTP_PORT` | `8080` |
| `INSTALL_DISK` | `/dev/nvme0n1` |
| `UBUNTU_VERSION` | `24.04.4` |
| `UBUNTU_CODENAME` | `noble` |
| `ALPINE_VERSION` | `3.22` |
| `BOOT_TOOLS` | `1` |
| `GRUB_TIMEOUT` | `5` |
| `PREPARE_ASSETS` | `1` |
| `SSH_KEY_REQUIRED` | `1` |
| `SSH_KEY_FILE` | `/etc/lernvirt/lerncloud.pub` |
| `SSH_PUBLIC_KEY_URL` | leer; wird nach Möglichkeit aus dem bisherigen `pxe/`-Setup übernommen |
| `PXE_STACK_ARCHIVE_URL` | `https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz` |
| `SUSE_ISO` | leer; bei SUSE Pfad oder URL angeben |

## Kontrolle

Server:

```bash
sudo /srv/tftp/bin/pxe-show
sudo systemctl status dnsmasq nginx --no-pager
sudo dnsmasq --test
sudo nginx -t
```

HTTP:

```bash
curl -I http://192.168.1.101:8080/
```

Ubuntu ISO:

```bash
curl -I http://192.168.1.101:8080/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso
```

OpenShift:

```bash
curl -I http://192.168.1.101:8080/linux/openshift/rootfs.img
curl -I http://192.168.1.101:8080/openshift/master.ign
```

## Referenzen

- Ubuntu Releases: `https://releases.ubuntu.com/`
- Alpine PXE: `https://wiki.alpinelinux.org/wiki/PXE_boot`
- Alpine Netboot: `https://dl-cdn.alpinelinux.org/alpine/`
- OpenShift 4.20 Bare Metal Installation: `https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_on_bare_metal/`
