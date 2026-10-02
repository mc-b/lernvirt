# lernvirt PXE Stack

`pxe-stack` stellt die PXE-Basis für lernvirt bereit. Die Basis ist bewusst auf Ubuntu-basierte Lernumgebungen reduziert. SUSE, OpenShift und HAProxy werden **nicht** durch `install-pxe.sh` eingerichtet, sondern über separate Add-on-Scripts.

## Architektur

Die PXE-Basis besteht aus:

- `dnsmasq` als Proxy-DHCP und TFTP
- GRUB UEFI Network Boot
- `nginx` fest auf **Port 80**
- Ubuntu Server Autoinstall
- lernvirt Stacks `ubuntu`, `cna`, `cna-full`, `platen` und `reset`
- Alpine und BusyBox als optionale RAM-/Boot-Tools ohne Installation
- SSH Public Key unter `/etc/lernvirt/lerncloud.pub`
- `/boot/lernvirt-installed` zur Umschaltung auf lokalen Boot

Optionale Komponenten:

- `install-suse.sh` installiert den SUSE-PXE-Stack
- `install-openshift.sh` installiert den OpenShift/RHCOS-PXE-Stack
- `install-haproxy.sh` richtet HAProxy separat für die OpenShift API/MCS ein

`install-pxe.sh` installiert **weder SUSE noch OpenShift noch HAProxy**.

## Installation

Direkt:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -
```

In cloud-init:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -']
```

Andere Basis-Stacks:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=ubuntu bash -
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna-full bash -
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=platen bash -
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=reset bash -
```

## Verzeichnisstruktur

```text
pxe-stack/
├── install-pxe.sh
├── install-suse.sh
├── install-openshift.sh
├── install-haproxy.sh
├── README.md
├── config/
│   └── rack.conf.example
├── autoinstall/
│   ├── user-data
│   └── user-data-reset
├── bin/
│   ├── import-legacy-autoinstall
│   ├── prepare-alpine
│   ├── prepare-ssh-key
│   ├── prepare-ubuntu
│   ├── pxe-prepare
│   ├── pxe-render
│   └── pxe-show
├── grub/
│   ├── grub.cfg
│   ├── boot-tools.cfg
│   └── stacks/
│       ├── _ubuntu-install.cfg
│       ├── ubuntu.cfg
│       ├── cna.cfg
│       ├── cna-full.cfg
│       ├── platen.cfg
│       └── reset.cfg
└── addons/
    ├── suse/
    │   ├── bin/prepare-suse
    │   └── grub/stacks/suse.cfg
    └── openshift/
        ├── bin/prepare-openshift
        ├── bin/prepare-openshift-ignition
        ├── config/openshift.conf.example
        └── grub/stacks/openshift.cfg
```

Nach der Basisinstallation liegen die Laufzeitdateien unter:

```text
/srv/tftp/
├── bin/
├── config/rack.conf
├── grub/
│   ├── grub.cfg
│   ├── hosts.cfg
│   ├── runtime.cfg
│   └── stacks/
└── linux/
```

HTTP-Inhalte liegen unter `/var/www/html` und werden durch nginx über Port 80 ausgeliefert.

## Host- und Stack-Auswahl

Die Hostregeln stehen in:

```text
/srv/tftp/config/rack.conf
```

Format:

```bash
HOSTS=(
    "MAC|STACK|VARIANT"
)
```

`*` gilt für alle Rechner. Die Regeln werden von oben nach unten ausgewertet; die **letzte passende Regel gewinnt**.

Alle Rechner CNA:

```bash
HOSTS=(
    "*|cna|"
)
```

Default CNA, ein Rechner CNA Full:

```bash
HOSTS=(
    "*|cna|"
    "80:EE:73:EF:0D:E9|cna-full|"
)
```

Nach Änderungen:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-show
```

## Reset

`reset` ist ein normaler Stack. Es gibt keine separate Reset-Sonderkonfiguration.

Globaler Reset für alle Rechner:

```bash
HOSTS=(
    "*|cna|"

    # andere Overrides ...

    "*|reset|"
)
```

Die letzte `*|reset|`-Regel gewinnt gegen alle vorherigen Regeln.

Der Reset-Stack installiert Ubuntu mit:

```text
user-data-reset
```

Die Reset-Autoinstallation:

- installiert Ubuntu neu
- übernimmt den SSH-Key
- aktiviert Wake-on-LAN
- erzeugt `/boot/lernvirt-installed`
- fährt den Rechner danach herunter

## `/boot/lernvirt-installed`

Bei jedem PXE-Boot sucht GRUB lokal nach:

```text
/boot/lernvirt-installed
```

Ist der Marker vorhanden, wird standardmässig das lokal installierte System gebootet.

Die lokale Partition wird dabei mit einer separaten GRUB-Variable gesucht:

```grub
search --no-floppy --file --set=localroot /boot/lernvirt-installed
```

Damit bleibt GRUBs `root` auf dem TFTP-Server und weitere TFTP-Dateien können weiterhin geladen werden.

Der Stack `reset` ignoriert den Marker bewusst und startet die Neuinstallation trotzdem.

## SSH Public Key

Der Standardpfad ist:

```text
/etc/lernvirt/lerncloud.pub
```

`prepare-ssh-key` verwendet in dieser Reihenfolge:

1. einen bereits vorhandenen Key unter `/etc/lernvirt/lerncloud.pub`
2. einen passenden Key aus dem heruntergeladenen lernvirt-Repository
3. `SSH_PUBLIC_KEY_URL`, falls gesetzt

Der Key wird für Autoinstall zusätzlich unter nginx bereitgestellt:

```text
http://192.168.1.101/ssh/lerncloud.pub
```

Die Ubuntu-Autoinstallation übernimmt ihn nach:

```text
/home/ubuntu/.ssh/authorized_keys
```

## Ubuntu Images

`prepare-ubuntu` lädt standardmässig:

```text
ubuntu-24.04.4-live-server-amd64.iso
```

und stellt bereit:

```text
TFTP: /srv/tftp/linux/ubuntu/noble/amd64/vmlinuz
TFTP: /srv/tftp/linux/ubuntu/noble/amd64/initrd
HTTP: /var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso
```

`install-pxe.sh` ruft `pxe-prepare` standardmässig automatisch auf.

Automatische Asset-Vorbereitung deaktivieren:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | PREPARE_ASSETS=0 STACK=cna bash -
```

Später manuell:

```bash
sudo /srv/tftp/bin/pxe-prepare
```

## Bestehende CNA/Platen Autoinstall-Dateien

Für `cna`, `cna-full` und `platen` werden die bestehenden lernvirt `user-data-*`-Dateien weiterverwendet.

Fehlt beispielsweise `user-data-cna`, versucht `import-legacy-autoinstall`, die Datei aus dem bisherigen `pxe/`-Bereich des lernvirt-Repositories zu übernehmen.

Bestehende Dateien unter:

```text
/var/www/html/autoinstall/
```

werden nicht überschrieben.

## Alpine und BusyBox

Alpine und BusyBox sind keine Installations-Stacks. Sie erscheinen als zusätzliche GRUB-Menüeinträge und laufen aus RAM.

Aktiv:

```bash
BOOT_TOOLS="1"
```

Deaktivieren:

```bash
BOOT_TOOLS="0"
sudo /srv/tftp/bin/pxe-render
```

Beide Varianten verwenden dieselben Alpine-Netboot-Artefakte.

## nginx

nginx ist Bestandteil der PXE-Basis und lauscht fest auf:

```text
TCP 80
```

Konfiguration:

```text
/etc/nginx/sites-available/pxe-stack
```

Der Standard-nginx-Site-Link wird entfernt und durch `pxe-stack` ersetzt.

Test:

```bash
curl -I http://192.168.1.101/
curl -I http://192.168.1.101/ssh/lerncloud.pub
```

Es gibt in der PXE-Basis **keine Port-8080-Sonderbehandlung mehr**.

## SUSE als separates Add-on

SUSE wird nicht von `install-pxe.sh` installiert.

Add-on installieren:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | bash -
```

Mit ISO und direkter Asset-Vorbereitung:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | \
  SUSE_ISO=/srv/iso/SLE-15-SP6-Full-x86_64-GM-Media1.iso bash -
```

Danach steht der Stack `suse` zur Verfügung:

```bash
HOSTS=(
    "*|suse|"
)
```

Optional kann `VARIANT` als AutoYaST-Dateiname verwendet werden:

```bash
HOSTS=(
    "*|suse|"
    "80:EE:73:EF:01:81|suse|terra4.xml"
)
```

AutoYaST-Dateien liegen unter:

```text
/var/www/html/autoyast/
```

nginx bleibt dabei auf Port 80.

## OpenShift als separates Add-on

OpenShift wird nicht von `install-pxe.sh` installiert.

PXE-Unterstützung und RHCOS Assets installieren:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | bash -
```

Die OpenShift-Konfiguration wird beim ersten Aufruf angelegt als:

```text
/srv/tftp/config/openshift.conf
```

Danach können Hosts beispielsweise so zugewiesen werden:

```bash
HOSTS=(
    "*|openshift|master"
    "80:EE:73:EF:01:81|openshift|worker"
)
```

Ignition wird bewusst separat ausgelöst, weil dafür Pull Secret und Cluster-Konfiguration vorhanden sein müssen:

```bash
sudo /srv/tftp/bin/prepare-openshift-ignition
```

Alternativ beim Add-on-Installer:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | \
  PREPARE_IGNITION=1 bash -
```

OpenShift ändert die nginx-Konfiguration nicht. RHCOS und Ignition werden ebenfalls über Port 80 ausgeliefert.

## HAProxy separat

HAProxy wird weder von `install-pxe.sh` noch von `install-openshift.sh` installiert.

Nach angepasster `/srv/tftp/config/openshift.conf`:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-haproxy.sh | bash -
```

Das Script konfiguriert nur:

```text
6443   OpenShift Kubernetes API
22623  Machine Config Server
```

Port 80 und Port 443 werden absichtlich nicht von diesem HAProxy-Script belegt. Damit bleibt nginx auf Port 80 unabhängig von HAProxy.

## Erweiterung um weitere Stacks

Die zentrale `grub.cfg` enthält keine feste Liste von Betriebssystemen.

Ein installierter Stack besteht mindestens aus:

```text
/srv/tftp/grub/stacks/<stack>.cfg
```

GRUB lädt dynamisch:

```grub
source (tftp,${tftp_server})/grub/stacks/${stack}.cfg
```

Ein Stack kann mit:

```text
# PXE-ASSET: name
```

optional einen Asset-Preparer referenzieren:

```text
/srv/tftp/bin/prepare-name
```

Damit können weitere Betriebssysteme als separate Add-ons ergänzt werden, ohne `install-pxe.sh` oder die zentrale `grub.cfg` zu erweitern.

## Wichtige Dateien auf dem PXE-Server

```text
/srv/tftp/config/rack.conf
/srv/tftp/grub/grub.cfg
/srv/tftp/grub/runtime.cfg
/srv/tftp/grub/hosts.cfg
/srv/tftp/grub/stacks/
/srv/tftp/bin/
/var/www/html/autoinstall/
/etc/lernvirt/lerncloud.pub
/etc/nginx/sites-available/pxe-stack
```

Status anzeigen:

```bash
sudo /srv/tftp/bin/pxe-show
```

GRUB-Konfiguration neu erzeugen:

```bash
sudo /srv/tftp/bin/pxe-render
```
