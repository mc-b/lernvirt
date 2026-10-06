# SUSE Harvester PXE Add-on

Harvester wird als Zusatz zur gemeinsamen PXE-Basis aus [README.md](README.md) installiert. Die allgemeine Host-Zuordnung erfolgt weiterhin über `/srv/tftp/config/rack.conf`; Harvester verwendet `VARIANT` für die Rolle und den Hostnamen.

## Installation

Eine freie Harvester-VIP ist zwingend erforderlich:

```bash
sudo HARVESTER_VIP=192.168.1.110 ./install-harvester.sh
```

Der Installer lädt die benötigten Harvester-Artefakte, ergänzt den GRUB-Stack und persistiert die Harvester-Konfiguration in `rack.conf`.

## Standardwerte

```bash
HARVESTER_VERSION=1.8.2
HARVESTER_ARCH=amd64
HARVESTER_DEVICE=/dev/nvme0n1
HARVESTER_INTERFACE=enp2s0
HARVESTER_SSH_KEY_FILE=/etc/lernvirt/lerncloud.pub
HARVESTER_NTP_SERVERS="0.suse.pool.ntp.org 1.suse.pool.ntp.org"
HARVESTER_SKIPCHECKS=true
```

Der Installer unterstützt `amd64` und `arm64`.

## Host-Regeln

Für Harvester muss jeder Node eine explizite MAC-Adresse besitzen. Die Variante hat das Format:

```text
create:HOSTNAME
join:HOSTNAME
```

Beispiel:

```bash
HOSTS=(
  "AA:BB:CC:DD:EE:01|harvester|create:harvester-1"
  "AA:BB:CC:DD:EE:02|harvester|join:harvester-2"
  "AA:BB:CC:DD:EE:03|harvester|join:harvester-3"
)
```

Der `create`-Node muss den Cluster zuerst initialisieren. Danach können die `join`-Nodes beitreten.

Nach Änderungen genügt wie bei allen Stacks:

```bash
sudo pxe-update
```

## Generierte Node-Konfiguration

`pxe-update` erzeugt aus den Harvester-Regeln pro MAC eine Konfiguration unter:

```text
/var/www/html/harvester/config/aa-bb-cc-dd-ee-ff.yaml
```

Diese Dateien enthalten unter anderem Cluster-Token und Passwort und werden aus `rack.conf` neu erzeugt. Der PXE-HTTP-Server sollte deshalb nur im Installationsnetz erreichbar sein.

## Ablauf

1. UEFI PXE lädt Kernel und Initramfs per TFTP.
2. Harvester RootFS und Node-Konfiguration werden per HTTP geladen.
3. Der erste Node startet mit `create`, weitere Nodes mit `join`.
4. Harvester installiert sich auf `HARVESTER_DEVICE`.
5. Nach dem Reboot erkennt GRUB den Harvester-COS-State und startet lokal.

## Artefakte

TFTP:

```text
/srv/tftp/linux/harvester/<version>/<arch>/
```

HTTP:

```text
/var/www/html/linux/harvester/<version>/<arch>/
```

Das ISO wird mit SHA512 geprüft. Weitere Artefakte werden geprüft, sofern passende Checksummen verfügbar sind.

## Konfiguration anpassen

Beispiel für eine andere Installationsdisk:

```bash
sudo HARVESTER_VIP=192.168.1.110 \
     HARVESTER_DEVICE=/dev/sda \
     ./install-harvester.sh
```

Für produktionsnähere Installationen können die Harvester-Checks wieder aktiviert werden:

```bash
sudo HARVESTER_VIP=192.168.1.110 \
     HARVESTER_SKIPCHECKS=false \
     ./install-harvester.sh
```

Harvester 1.8 verwendet UEFI; die generierten Konfigurationen setzen entsprechend `force_efi: true`.

## Zugangsdaten

Falls `HARVESTER_TOKEN` und `HARVESTER_PASSWORD` nicht vorgegeben werden, erzeugt der Installer Werte und persistiert sie in der PXE-Konfiguration. Diese Werte sowie die generierten Node-YAMLs sind vertraulich zu behandeln.

## Quellen

- Harvester-Dokumentation: https://docs.harvesterhci.io/
- Harvester Releases: https://github.com/harvester/harvester/releases
- PXE Boot: https://docs.harvesterhci.io/latest/install/pxe-boot-install/
