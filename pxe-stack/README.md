# lernvirt PXE Stack

`pxe-stack` stellt eine gemeinsame UEFI-PXE-Basis für automatisierte Installationen im lernvirt-Labor bereit. Die Basis übernimmt DHCP/PXE-Integration, TFTP, GRUB und HTTP. Die eigentliche Installation wird über austauschbare Stacks ausgewählt.

## Architektur

| Komponente | Aufgabe | Pfad / Port |
|---|---|---|
| `dnsmasq` | Proxy-DHCP, PXE und TFTP | `/etc/dnsmasq.d/pxe.conf` |
| TFTP | GRUB, Kernel und Initramfs | `/srv/tftp` |
| GRUB | Stack-Auswahl und lokaler Boot | `/srv/tftp/grub` |
| nginx | ISO-, RootFS- und Konfigurationsdateien | `/var/www/html`, Port 80 |
| `rack.conf` | Zentrale Laufzeitkonfiguration und Host-Zuordnung | `/srv/tftp/config/rack.conf` |
| `pxe-update` | Erzeugt GRUB-Laufzeitkonfigurationen | `/usr/local/sbin/pxe-update` |
| `pxe-show` | Zeigt den aktuellen PXE-Status | `/usr/local/sbin/pxe-show` |

Die Basis wird durch `install-pxe.sh` eingerichtet. Zusätzliche Plattformen wie SUSE, Harvester und OpenShift besitzen eigene Installer und ergänzen die gemeinsame PXE-Infrastruktur.

## Installation

Als `root`:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | bash -
```

Oder z. B. mit einem anderen Standard-Stack:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -
```

Typische Vorgaben können über Umgebungsvariablen geändert werden, unter anderem:

```bash
INSTALL_DISK=/dev/nvme0n1
UBUNTU_VERSION=24.04.4
UBUNTU_CODENAME=noble
ALPINE_VERSION=3.22
BOOT_TOOLS=1
GRUB_TIMEOUT=5
SSH_KEY_FILE=/etc/lernvirt/lerncloud.pub
```

Für cloud-init genügt beispielsweise:

```yaml
#cloud-config
runcmd:
  - curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | bash -
```

## Stacks

Die vorhandenen Installationspfade sind auf eigene Dokumente verteilt:

| Stack | Beschreibung | Dokumentation |
|---|---|---|
| `ubuntu` | Ubuntu Server Autoinstall | [UBUNTU.md](UBUNTU.md) |
| `cna-control`, `cna-control-full` | Ubuntu-basierte lernvirt-Profile | [UBUNTU.md](UBUNTU.md) und [CNA](https://gitlab.com/ch-tbz-wb/Stud/CnA/-/tree/main/0_Organisatorisches/Infrastruktur/pxe-stack) |
| `reset` | Erneuter Ubuntu-Autoinstall unabhängig vom Installationsmarker | [UBUNTU.md](UBUNTU.md) |
| `suse` | openSUSE Leap mit optionalem RKE2/Rancher-Bootstrap | [SUSE.md](SUSE.md) |
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
sudo pxe-update
sudo pxe-show
```

`pxe-update` erzeugt daraus unter anderem `runtime.cfg` und `hosts.cfg` für GRUB.

## Boot-Ablauf

1. Der Client startet per UEFI PXE.
2. `dnsmasq` liefert den passenden GRUB-EFI-Bootloader.
3. GRUB liest die Laufzeit- und Host-Konfiguration.
4. Der zugewiesene Stack wird geladen.
5. Ist bereits eine lernvirt-Installation erkannt, wird normalerweise lokal gebootet.

Für normale Installationen dient `/boot/lernvirt-installed` als Marker. RHCOS kann den Marker zusätzlich als `/lernvirt-installed` auf einer separaten Boot-Partition bereitstellen. Harvester verwendet seine eigene COS-State-Erkennung.

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

## Wichtige Pfade

```text
/srv/tftp/
├── config/rack.conf
├── grub/
├── linux/
└── ...

/var/www/html/
├── autoinstall/
├── linux/
└── ...
```

Status prüfen:

```bash
sudo pxe-show
```

## Eigenen Stack ergänzen

Ein einfacher zusätzlicher Stack besteht aus einer GRUB-Konfiguration unter:

```text
/srv/tftp/grub/stacks/<stack>.cfg
```

Der Stack kann `VARIANT` aus der Host-Regel verwenden und Kernel, Initramfs oder weitere Daten über TFTP bzw. HTTP laden. Für Plattformen mit zusätzlichen generierten Konfigurationen kann ein eigener Installer oder eine Erweiterung von `pxe-update` erforderlich sein.
