# lernvirt PXE Stack

`pxe-stack` erweitert die bestehende, funktionierende `pxe/install-pxe.sh` um eine generische Stack-/Hostauswahl. Die PXE-Basis selbst bleibt dabei kompatibel zur bisherigen Implementierung: Netzwerkdaten werden automatisch ermittelt, `dnsmasq` läuft als Proxy-DHCP/TFTP ohne fest verdrahtetes Interface und nginx liefert die Installationsdateien auf Port 80 aus.

## Installation

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -
```

Optional mit einem vorgegebenen Public Key:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | \
  STACK=cna \
  SSH_PUBLIC_KEY_URL=https://raw.githubusercontent.com/mc-b/lerncloud/main/ssh/lerncloud.pub \
  bash -
```

Für cloud-init:

```yaml
#cloud-config
runcmd:
  - [bash, -lc, 'curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -']
```

## Was `install-pxe.sh` einrichtet

- automatische Ermittlung von Default-Interface, IPv4-Adresse, Netz und Netzmaske
- `dnsmasq` als Proxy-DHCP und TFTP entsprechend der bisherigen `pxe/install-pxe.sh`
- x86_64- und ARM64-UEFI-PXE (`grubx64.efi`, `grubaa64.efi`)
- Ubuntu Server ISO für amd64 und arm64
- nginx auf Port 80 mit `/var/www/html`
- SSH-Key für den Benutzer `ubuntu`; alternativ kann `SSH_PUBLIC_KEY_URL` vorgegeben werden
- Stack-/Hostauswahl über `rack.conf`
- `/boot/lernvirt-installed` für lokalen Boot
- `reset` als normaler Stack mit `user-data-reset`
- Alpine/BusyBox optional als RAM-Bootvarianten ohne Installation

SUSE, OpenShift und HAProxy sind **kein Bestandteil von `install-pxe.sh`**. Sie werden ausschliesslich durch ihre separaten Add-on-Scripts eingerichtet.

## Stacks

Die PXE-Basis enthält:

```text
ubuntu
cna
cna-full
platen
reset
```

`reset` installiert Ubuntu mit `user-data-reset`. Die Reset-Autoinstallation entfernt `/boot/lernvirt-installed`, aktiviert Wake-on-LAN und fährt den Rechner anschliessend herunter.

## Hostauswahl

Die Konfiguration liegt unter:

```text
/srv/tftp/config/rack.conf
```

Regelformat:

```bash
HOSTS=(
    "MAC|STACK|VARIANT"
)
```

`*` gilt für alle Rechner. Regeln werden von oben nach unten ausgewertet; die letzte passende Regel gewinnt.

Alle Rechner CNA:

```bash
HOSTS=(
    "*|cna|"
)
```

Default CNA, einzelner Host CNA Full:

```bash
HOSTS=(
    "*|cna|"
    "80:EE:73:EF:0D:E9|cna-full|"
)
```

Globaler Reset:

```bash
HOSTS=(
    "*|cna|"
    "80:EE:73:EF:0D:E9|cna-full|"

    "*|reset|"
)
```

Nach Änderungen:

```bash
sudo /srv/tftp/bin/pxe-render
sudo /srv/tftp/bin/pxe-show
```

## PXE Netzwerk

Die Netzwerkparameter werden wie in `pxe/install-pxe.sh` automatisch ermittelt:

```bash
IFACE="$(ip -4 route show default | awk '{print $5; exit}')"
```

`dnsmasq` wird **nicht** auf einen erfundenen oder fest konfigurierten Interface-Namen gebunden. Die relevante Konfiguration entspricht dem bisherigen Ansatz:

```ini
port=0

dhcp-range=<Subnetz>,proxy,<Netzmaske>

#interface=<ermitteltes Interface>
#bind-interfaces
bind-dynamic

dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:efi-arm64,option:client-arch,11

dhcp-boot=tag:efi-x86_64,grubx64.efi
dhcp-boot=tag:efi-arm64,grubaa64.efi

dhcp-option-force=66,<PXE-IP>

enable-tftp
tftp-root=/srv/tftp
```

Die Logs liegen standardmässig unter:

```text
/var/log/dnsmasq-pxe.log
```

## Ubuntu Images

Wie beim bisherigen Installer werden beide Architekturen vorbereitet:

```text
/var/www/html/linux/ubuntu/noble/amd64/ubuntu-24.04.4-live-server-amd64.iso
/var/www/html/linux/ubuntu/noble/arm64/ubuntu-24.04.4-live-server-arm64.iso

/srv/tftp/amd64/vmlinuz
/srv/tftp/amd64/initrd
/srv/tftp/arm64/vmlinuz
/srv/tftp/arm64/initrd
```

## SSH

Ohne `SSH_PUBLIC_KEY_URL` wird das bisherige Verhalten verwendet:

```text
/home/ubuntu/.ssh/id_rsa_lernvirt
/home/ubuntu/.ssh/id_rsa_lernvirt.pub
```

Fehlt der Key, wird er erzeugt. Der Public Key wird zusätzlich unter:

```text
/etc/lernvirt/lerncloud.pub
```

bereitgestellt und in die vorhandenen `user-data*`-Dateien eingefügt.

## `/boot/lernvirt-installed`

Beim PXE-Boot wird lokal nach:

```text
/boot/lernvirt-installed
```

gesucht. Ist der Marker vorhanden, ist der lokale Boot standardmässig ausgewählt. Dabei wird eine separate GRUB-Variable `localroot` verwendet, damit der TFTP-Zugriff für die Stack-Konfiguration erhalten bleibt.

Der Stack `reset` ignoriert den Marker bewusst und startet die Reset-Installation.

## Alpine / BusyBox

Mit:

```bash
BOOT_TOOLS=1
```

werden Alpine und eine BusyBox-Shell zusätzlich im x86_64-GRUB-Menü angeboten. Beide laufen im RAM und installieren nichts auf die lokale Platte. Alpine wird mit `console=tty0` und `nomodeset` gestartet, damit die Textkonsole auf physischer Hardware sichtbar bleibt. Die BusyBox-Variante verwendet den von Alpine unterstützten Kernelparameter `single` und öffnet eine `ash`-Shell im Alpine-initramfs; mit `exit` wird der normale Alpine-Boot fortgesetzt.

Die Netboot-Dateien werden atomar geladen und gegen die vom HTTP-Server gemeldete Dateigrösse geprüft. Ein früher abgebrochener Download wird dadurch nicht mehr als gültiges Asset wiederverwendet. Für ein erzwungenes Neuladen kann auf dem PXE-Server ausgeführt werden:

```bash
ALPINE_FORCE=1 /srv/tftp/bin/prepare-alpine
```

Deaktivieren:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna BOOT_TOOLS=0 bash -
```

## Separate Add-ons

SUSE:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | bash -
```

OpenShift:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | bash -
```

HAProxy:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-haproxy.sh | bash -
```

Diese Komponenten werden durch `install-pxe.sh` weder installiert noch konfiguriert.
