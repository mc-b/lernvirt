# lernvirt PXE Stack

`pxe-stack` stellt eine gemeinsame UEFI-PXE-Basis für automatisierte Installationen im lernvirt-Labor bereit. Die Basis übernimmt DHCP/PXE-Integration, TFTP, GRUB und HTTP. Die eigentliche Installation wird über austauschbare Stacks ausgewählt.

## PXE-Workflow

Der PXE-Betrieb besteht aus zwei getrennten Abläufen: **Konfiguration** und **Bootvorgang**.

### 1. Konfigurations-Workflow

| Komponente     | Aufgabe                                                  | Pfad                         |
| -------------- | -------------------------------------------------------- | ---------------------------- |
| **rack.conf**  | Zentrale Laufzeitkonfiguration und Host-Zuordnung        | `/srv/tftp/config/rack.conf` |
| **pxe-update** | Erzeugt die GRUB-Laufzeitkonfigurationen aus `rack.conf` | `/srv/tftp/bin/pxe-update` |
| **pxe-show**   | Zeigt den aktuellen PXE-Status und die Host-Zuordnungen  | `/srv/tftp/bin/pxe-show`   |

### 2. PXE-Boot-Workflow

| Schritt | Komponente  | Aufgabe                                                              | Pfad / Port                |
| ------- | ----------- | -------------------------------------------------------------------- | -------------------------- |
| 1       | **dnsmasq** | Proxy-DHCP und PXE-Bootinformationen                                 | `/etc/dnsmasq.d/pxe.conf`  |
| 2       | **TFTP**    | Liefert GRUB, Kernel und Initramfs                                   | `/srv/tftp`                |
| 3       | **GRUB**    | Stack-Auswahl anhand der generierten Konfiguration oder lokaler Boot | `/srv/tftp/grub`           |
| 4       | **nginx**   | Liefert ISO-, RootFS- und Konfigurationsdateien per HTTP             | `/var/www/html`, Port `80` |

## Installation

Als `root`:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | bash -
```

## Stacks

Die vorhandenen Installationspfade sind auf eigene Dokumente verteilt:

| Stack | Beschreibung | Dokumentation |
|---|---|---|
| `ubuntu` | Ubuntu Server Autoinstall (user-data) | [UBUNTU.md](UBUNTU.md) |
| `cna-control`, `cna-control-full` | Modul Cloud-native & Advanced | [UBUNTU.md](UBUNTU.md) und [CNA](https://gitlab.com/ch-tbz-wb/Stud/CnA/-/tree/main/0_Organisatorisches/Infrastruktur/pxe-stack) |
| `reset` | Reset HW (user-data-reset), z.B. nach OpenShift Installation | [UBUNTU.md](UBUNTU.md) |
| `suse` | openSUSE Leap mit RKE2/Rancher-Bootstrap | [SUSE.md](SUSE.md) |
| `harvester` | SUSE Harvester | [HARVESTER.md](HARVESTER.md) |
| `openshift` | Red Hat OpenShift / RHCOS | [OPENSHIFT.md](OPENSHIFT.md) |

## Host-Zuordnung mit `rack.conf`

Die Datei `/srv/tftp/config/rack.conf` enthält globale Einstellungen und die Host-Regeln. Das Format einer Regel ist:

```text
MAC|STACK|VARIANT
```

Beispiel:

```bash
HOSTS=(
  "*|ubuntu|"
  "AA:BB:CC:DD:EE:FF|suse|"
)
```

Die letzte passende Regel gewinnt. `VARIANT` ist optional und wird vom jeweiligen Stack interpretiert.

Nach Änderungen:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

`pxe-update` erzeugt daraus unter anderem `runtime.cfg` und `hosts.cfg` für GRUB.

## Eigenen Stack ergänzen

Ein einfacher zusätzlicher Stack besteht aus einer GRUB-Konfiguration unter:

```text
/srv/tftp/grub/stacks/<stack>.cfg
```

Der Stack kann `VARIANT` aus der Host-Regel verwenden und Kernel, Initramfs oder weitere Daten über TFTP bzw. HTTP laden. Für Plattformen mit zusätzlichen generierten Konfigurationen kann ein eigener Installer oder eine Erweiterung von `pxe-update` erforderlich sein.

Beispiele:
* [Cloud-native Advanced](https://gitlab.com/ch-tbz-wb/Stud/CnA/-/tree/main/0_Organisatorisches/Infrastruktur/pxe-stack)
* [GNS3](https://gitlab.com/ch-tbz-wb/Stud/nwa/-/tree/main/0_Organisatorisches/Infrastruktur/pxe-stack)

## Alpine / BusyBox Boot Tools

Mit `BOOT_TOOLS=1` stellt die PXE-Basis zusätzliche RAM-basierte Werkzeuge bereit. Sie installieren nichts auf die lokale Disk.

Aktuell werden die Alpine-Netboot-Artefakte für `x86_64` vorbereitet:

- **Alpine Linux (RAM, keine Installation)**
- **BusyBox Shell (Alpine initramfs, keine Installation)**

Kernel und Initramfs liegen unter TFTP, `modloop-lts` wird über HTTP geladen. Die BusyBox-Variante startet Alpine im Single-User-Modus. Für diese Boot-Tools ist standardmässig kein Root-Passwort gesetzt.

Deaktivieren:

```bash
sudo sed -i 's/^BOOT_TOOLS=.*/BOOT_TOOLS=0/' /srv/tftp/config/rack.conf
sudo pxe-update
```
