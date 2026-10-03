# SUSE Harvester PXE Add-on

Harvester wird als eigenständiger Add-on-Stack in die bestehende `pxe-stack`-Basis integriert. Es braucht kein separates `prepare-*`-Script.

## Dateien

Im Repository werden benötigt:

```text
pxe-stack/
├── install-harvester.sh       # neu
├── HARVESTER.md               # neu, Dokumentation
└── grub/
    └── grub.cfg               # geändert: COS_STATE als lokale Harvester-Installation erkennen
```

Keine Änderung ist nötig an:

```text
bin/pxe-update
bin/pxe-show
dnsmasq/nginx-Konfiguration
rack.conf-Format
```

`install-harvester.sh` erzeugt zur Laufzeit zusätzlich:

```text
/srv/tftp/linux/harvester/v1.8.2/amd64/vmlinuz
/srv/tftp/linux/harvester/v1.8.2/amd64/initrd
/srv/tftp/grub/stacks/harvester.cfg

/var/www/html/linux/harvester/v1.8.2/amd64/harvester.iso
/var/www/html/linux/harvester/v1.8.2/amd64/rootfs.squashfs
/var/www/html/harvester/config/config-create.yaml.example
/var/www/html/harvester/config/config-join.yaml.example
```

Die Version und Architektur können mit `HARVESTER_VERSION` und `HARVESTER_ARCH` überschrieben werden.

## Installation des Add-ons

Auf einem bereits eingerichteten PXE-Server:

```bash
sudo ./install-harvester.sh
```

Oder nach dem Commit ins Repository:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-harvester.sh | sudo bash -
```

Standard ist Harvester `1.8.2` für `amd64`.

Andere Architektur:

```bash
HARVESTER_ARCH=arm64 sudo ./install-harvester.sh
```

Erzwungener erneuter Download:

```bash
HARVESTER_FORCE=1 sudo ./install-harvester.sh
```

Der Installer lädt die offiziellen Harvester-PXE-Artefakte von `releases.rancher.com`. Das vollständige ISO wird mit der offiziellen SHA512-Prüfsumme geprüft. Falls die Prüfsummendatei auch Einträge für Kernel, initrd oder rootfs enthält, werden diese ebenfalls geprüft.

## CREATE-Konfiguration

Das Script erzeugt:

```text
/var/www/html/harvester/config/config-create.yaml.example
```

Für den ersten Node kopieren:

```bash
sudo cp \
  /var/www/html/harvester/config/config-create.yaml.example \
  /var/www/html/harvester/config/node1.yaml

sudo vi /var/www/html/harvester/config/node1.yaml
```

Mindestens anpassen:

- `token`
- `os.hostname`
- `os.password`
- Name des Management-Interfaces
- `install.device`
- `install.vip`

Bei mehreren lokalen Datenträgern sollte statt `/dev/sdX` oder `/dev/nvmeXnY` möglichst `/dev/disk/by-id/...` oder `/dev/disk/by-path/...` verwendet werden.

## JOIN-Konfiguration

Für weitere Nodes:

```bash
sudo cp \
  /var/www/html/harvester/config/config-join.yaml.example \
  /var/www/html/harvester/config/node2.yaml

sudo vi /var/www/html/harvester/config/node2.yaml
```

Zusätzlich zu Hostname, Passwort, Interface und Disk müssen vor allem gesetzt werden:

```yaml
server_url: "https://<HARVESTER-VIP>:443"
token: "<GLEICHER-CLUSTER-TOKEN>"
```

Die Konfigurationsdateien enthalten Zugangsdaten. Der HTTP-Dienst des PXE-Servers darf deshalb nur aus dem vorgesehenen Installationsnetz erreichbar sein.

## `rack.conf`

Die `VARIANT` ist bei Harvester der Name der YAML-Konfigurationsdatei unter `/var/www/html/harvester/config/`.

Beispiel für drei Nodes:

```bash
HOSTS=(
    "AA:BB:CC:DD:EE:01|harvester|node1.yaml"
    "AA:BB:CC:DD:EE:02|harvester|node2.yaml"
    "AA:BB:CC:DD:EE:03|harvester|node3.yaml"
)
```

Danach:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

Eine leere Variante wird absichtlich nicht automatisch installiert, weil Harvester bei einer PXE-Installation eine Konfigurationsdatei benötigt.

## Zweiter PXE-Boot / lokaler Boot

Harvester basiert auf Elemental und legt den lokalen GRUB-Bootloader auf der Partition mit dem Label `COS_STATE` ab.

Die angepasste `grub/grub.cfg` erkennt deshalb neben `/boot/lernvirt-installed` und `/lernvirt-installed` zusätzlich `COS_STATE`. Nach erfolgreicher Installation wird beim nächsten PXE-Boot standardmässig das lokale Harvester gebootet. Der vorhandene Local-Boot-Eintrag kann dazu `/grub2/grub.cfg` auf `COS_STATE` laden.

`install-harvester.sh` ergänzt diese Erkennung auch idempotent auf einem bereits installierten PXE-Server. Vor der ersten Änderung wird dort eine Sicherung angelegt:

```text
/srv/tftp/grub/grub.cfg.pre-harvester
```

## Hinweise zu Harvester 1.8

Neue PXE-Installationen von Harvester 1.8 müssen im UEFI-Modus booten. Während der PXE-Installation wird das vollständige ISO in den Arbeitsspeicher geladen; dafür werden mindestens 8 GiB RAM benötigt. Die regulären Harvester-Hardwareanforderungen für den späteren Betrieb gelten zusätzlich.

Die hier verwendeten Bootparameter entsprechen dem offiziellen Harvester-PXE-Verfahren:

```text
ip=dhcp
net.ifnames=1
rd.cos.disable
rd.noverifyssl
console=tty1
root=live:http://<PXE>/.../rootfs.squashfs
harvester.install.automatic=true
harvester.install.config_url=http://<PXE>/harvester/config/<datei.yaml>
```

## Quellen

- Harvester PXE Boot Installation: https://docs.harvesterhci.io/v1.8/install/pxe-boot-install/
- Harvester Configuration: https://docs.harvesterhci.io/v1.8/install/harvester-configuration/
- SUSE Virtualization 1.8.2 Release Notes: https://documentation.suse.com/cloudnative/virtualization/v1.8/en/release-notes/v1.8.2.html
