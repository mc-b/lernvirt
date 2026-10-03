# SUSE Harvester PXE Add-on

Harvester wird als Add-on in die bestehende `pxe-stack`-Basis integriert. Die Installation der einzelnen Nodes erfolgt vollständig unattended; pro Node muss keine YAML-Datei mehr manuell erstellt werden.

## Installation des Add-ons

Auf einem bereits eingerichteten PXE-Server aus dem ausgepackten Paket:

```bash
sudo HARVESTER_VIP=192.168.1.110 ./install-harvester.sh
```

`HARVESTER_VIP` ist die einzige Angabe, die nicht zuverlässig automatisch bestimmt werden kann. Sie muss eine freie statische Adresse im Management-Netz sein.

Beim ersten Aufruf werden automatisch erzeugt und in `/srv/tftp/config/rack.conf` gespeichert:

- `HARVESTER_TOKEN`
- `HARVESTER_PASSWORD`

Zusätzlich werden dort Version, Architektur, VIP, Installationsdisk, Management-Interface und SSH-Key-Datei hinterlegt.

Standardwerte:

```text
HARVESTER_VERSION=1.8.2
HARVESTER_ARCH=amd64
HARVESTER_DEVICE=<INSTALL_DISK aus rack.conf>
HARVESTER_INTERFACE=mgmt0
HARVESTER_SSH_KEY_FILE=/etc/lernvirt/lerncloud.pub
HARVESTER_NTP_SERVERS="0.suse.pool.ntp.org 1.suse.pool.ntp.org"
```

Das Management-Interface `mgmt0` muss nicht dem ursprünglichen Linux-Interfacenamen entsprechen. Der GRUB-Stack bindet beim Boot die PXE-MAC mittels `ifname=mgmt0:<MAC>` an diesen Namen.

## `rack.conf`

Das bestehende Format `MAC|STACK|VARIANT` bleibt unverändert. Für Harvester enthält `VARIANT` Installationsmodus und Hostname:

```bash
HOSTS=(
    "*|ubuntu|"
    "AA:BB:CC:DD:EE:01|harvester|create:harvester-01"
    "AA:BB:CC:DD:EE:02|harvester|join:harvester-02"
    "AA:BB:CC:DD:EE:03|harvester|join:harvester-03"
)
```

Für Harvester ist eine explizite MAC-Adresse erforderlich; `*|harvester|...` ist nicht zulässig.

Nach Änderungen:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

`pxe-update` erzeugt daraus automatisch:

```text
/var/www/html/harvester/config/aa-bb-cc-dd-ee-01.yaml
/var/www/html/harvester/config/aa-bb-cc-dd-ee-02.yaml
/var/www/html/harvester/config/aa-bb-cc-dd-ee-03.yaml
```

Die Dateien enthalten Token und Passwort. Sie werden bei jedem `pxe-update` vollständig aus `rack.conf` neu aufgebaut; veraltete Hostkonfigurationen werden entfernt.

## Automatischer Ablauf

```text
UEFI PXE
  -> MAC wird durch hosts.cfg einem Harvester-Stack zugeordnet
  -> Kernel + initrd per TFTP
  -> rootfs.squashfs per HTTP
  -> automatisch erzeugte Host-YAML per HTTP
  -> CREATE oder JOIN ohne Interaktion
  -> Installation auf HARVESTER_DEVICE
  -> Reboot
  -> COS_STATE wird von PXE-GRUB erkannt
  -> lokaler Harvester-Boot
```

Der erste Node verwendet `create:<hostname>`. Weitere Nodes verwenden `join:<hostname>` und erhalten automatisch `server_url: https://<HARVESTER_VIP>:443` sowie denselben Cluster-Token.

Der CREATE-Node muss erreichbar sein, bevor JOIN-Nodes erfolgreich beitreten können. Bei mehreren physischen Nodes daher zuerst den CREATE-Node starten und danach die JOIN-Nodes booten.

## Dateien und Verzeichnisse

Der Installer lädt die offiziellen Harvester-PXE-Artefakte nach:

```text
/srv/tftp/linux/harvester/v1.8.2/amd64/vmlinuz
/srv/tftp/linux/harvester/v1.8.2/amd64/initrd

/var/www/html/linux/harvester/v1.8.2/amd64/harvester.iso
/var/www/html/linux/harvester/v1.8.2/amd64/rootfs.squashfs
```

Der GRUB-Stack liegt unter:

```text
/srv/tftp/grub/stacks/harvester.cfg
```

Das ISO wird gegen die offizielle SHA512-Prüfsumme geprüft. Falls die Harvester-Prüfsummendatei auch Kernel, initrd oder rootfs enthält, werden diese ebenfalls validiert.

## Andere Werte verwenden

Beispiel mit eigener Installationsdisk:

```bash
sudo \
  HARVESTER_VIP=192.168.1.110 \
  HARVESTER_DEVICE=/dev/disk/by-id/nvme-SAMSUNG_... \
  ./install-harvester.sh
```

Bei mehreren Datenträgern ist `/dev/disk/by-id/...` oder `/dev/disk/by-path/...` gegenüber `/dev/sdX` bzw. `/dev/nvmeXnY` vorzuziehen.

Eigenen Token und eigenes Passwort setzen:

```bash
sudo \
  HARVESTER_VIP=192.168.1.110 \
  HARVESTER_TOKEN='mein-cluster-token' \
  HARVESTER_PASSWORD='mein-passwort' \
  ./install-harvester.sh
```

Erneuter Download der Assets:

```bash
sudo HARVESTER_FORCE=1 ./install-harvester.sh
```

## UEFI und lokaler Boot

Harvester v1.8 verlangt für neue PXE-Installationen UEFI. Der erzeugte Installationsstack setzt zusätzlich `force_efi: true`.

Nach erfolgreicher Installation erkennt `grub/grub.cfg` Harvester beim nächsten PXE-Boot über die Partition `COS_STATE`. Diese Erkennung wird nur angewendet, wenn für den Rechner weiterhin der Stack `harvester` gewählt ist. Ein späterer Wechsel auf einen anderen Installationsstack bleibt dadurch möglich.

## Sicherheit

Die automatisch erzeugten YAML-Dateien enthalten den Harvester-Cluster-Token und das OS-Passwort. Der HTTP-Dienst des PXE-Servers sollte deshalb nur im vorgesehenen Installationsnetz erreichbar sein.

## Quellen

- Harvester PXE Boot Installation: https://docs.harvesterhci.io/v1.8/install/pxe-boot-install/
- Harvester Configuration: https://docs.harvesterhci.io/v1.8/install/harvester-configuration/
- SUSE Virtualization 1.8.2 Release Notes: https://documentation.suse.com/cloudnative/virtualization/v1.8/en/release-notes/v1.8.2.html
