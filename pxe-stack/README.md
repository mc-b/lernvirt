# lernvirt PXE Stack

`pxe-stack` stellt die PXE-Basis für lernvirt bereit und ordnet Rechnern über eine zentrale `rack.conf` einen Boot-/Installations-Stack zu.

Ein **Stack** ist eine GRUB-Bootdefinition. Beispiele:

- `ubuntu` – Ubuntu Server Autoinstall mit `user-data`
- `cna` – Ubuntu mit `user-data-cna`
- `cna-full` – Ubuntu mit `user-data-cna-full`
- `platen` – Ubuntu mit `user-data-platen`
- `reset` – Ubuntu mit `user-data-reset`, um Rechner auf den Ausgangszustand zurückzusetzen
- `suse` – wird durch `install-suse.sh` ergänzt
- `openshift` – wird durch `install-openshift.sh` ergänzt

Die PXE-Basis verwendet `dnsmasq` als Proxy-DHCP/TFTP, GRUB UEFI und `nginx` auf Port 80. Ubuntu wird für amd64 und arm64 vorbereitet. Alpine/BusyBox sind optionale Boot-Tools und keine Installationsstacks.

## Installation / cloud-init

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

`install-pxe.sh` erledigt die PXE-Basis vollständig:

1. Netzwerk und PXE-Server-IP wie im bestehenden `pxe/install-pxe.sh` automatisch ermitteln
2. dnsmasq, nginx und GRUB installieren
3. Ubuntu 24.04.4 für amd64 und arm64 herunterladen
4. Kernel und initrd aus den ISOs extrahieren
5. GRUB UEFI für x86_64 und ARM64 bereitstellen
6. SSH-Key erzeugen bzw. übernehmen und in die Autoinstall-Dateien eintragen
7. bestehende CNA/Platen `user-data-*` aus dem lernvirt-Repository übernehmen
8. Alpine/BusyBox Assets herunterladen, sofern `BOOT_TOOLS=1`
9. `rack.conf` erzeugen, falls noch keine vorhanden ist
10. die aktive GRUB-Konfiguration erzeugen und dnsmasq/nginx starten

Es gibt keine separaten `prepare-*`-Scripts.

## Laufende Installation konfigurieren

Die zentrale Konfiguration liegt unter:

```text
/srv/tftp/config/rack.conf
```

Beispiel:

```bash
PXE_SERVER="192.168.1.101"
TFTP_ROOT="/srv/tftp"
HTTP_ROOT="/var/www/html"
INSTALL_DISK="/dev/nvme0n1"

UBUNTU_VERSION="24.04.4"
UBUNTU_CODENAME="noble"
ALPINE_VERSION="3.22"
BOOT_TOOLS="1"
GRUB_TIMEOUT="5"

HOSTS=(
    "*|cna|"
)
```

Format einer Hostregel:

```text
MAC|STACK|VARIANT
```

`*` gilt für alle Rechner. Die Regeln werden von oben nach unten ausgewertet; die **letzte passende Regel gewinnt**.

Alle Rechner CNA:

```bash
HOSTS=(
    "*|cna|"
)
```

Ein einzelner Rechner CNA Full:

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

Nach jeder Änderung an `rack.conf`:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

`pxe-update` macht nur eine Aufgabe: `rack.conf` in die von GRUB verwendeten `runtime.cfg` und `hosts.cfg` umsetzen.

`pxe-show` zeigt die Hostregeln und die installierten Stacks. Es warnt, wenn `rack.conf` neuer als die aktive GRUB-Konfiguration ist.

## `/boot/lernvirt-installed`

GRUB sucht beim PXE-Boot lokal nach:

```text
/boot/lernvirt-installed
```

Ist der Marker vorhanden, wird standardmässig das lokale System gebootet.

Der `reset`-Stack ignoriert diesen Marker bewusst und startet trotzdem die Reset-Installation.

Die normale lernvirt-Autoinstallation erzeugt den Marker am Ende der Installation. Die Reset-Autoinstallation entfernt ihn und aktiviert Wake-on-LAN, bevor der Rechner ausgeschaltet wird.

## Alpine / BusyBox

Alpine und BusyBox sind zusätzliche RAM-Bootvarianten. Sie installieren nichts auf die lokale Platte.

Aktivieren bzw. deaktivieren:

```bash
BOOT_TOOLS="1"
```

oder:

```bash
BOOT_TOOLS="0"
```

Anschliessend:

```bash
sudo /srv/tftp/bin/pxe-update
```

Die Alpine-Netboot-Assets werden durch `install-pxe.sh` selbst heruntergeladen.

## SUSE Add-on

SUSE wird vollständig separat eingerichtet:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-suse.sh | bash -
```

`install-suse.sh` erledigt selbständig:

- openSUSE Leap 15.6 DVD herunterladen
- SHA256 prüfen
- Kernel und initrd extrahieren
- den vollständigen Installationsbaum unter nginx bereitstellen
- `suse.cfg` installieren
- `pxe-update` ausführen

Danach kann `rack.conf` z.B. so gesetzt werden:

```bash
HOSTS=(
    "*|suse|"
)
```

Optional mit AutoYaST-Datei:

```bash
HOSTS=(
    "*|suse|lab.xml"
)
```

Die Datei liegt dann unter:

```text
/var/www/html/autoyast/lab.xml
```

Für ein eigenes SLES-ISO:

```bash
SUSE_ISO=/pfad/SLE-15-SP6-Full-x86_64-GM-Media1.iso ./install-suse.sh
```

## OpenShift Add-on

OpenShift/RHCOS wird separat eingerichtet:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | bash -
```

Vor der vollständigen Ignition-Erzeugung muss ein Pull Secret vorhanden sein:

```text
/etc/lernvirt/pull-secret.json
```

`install-openshift.sh` erledigt:

- `openshift-install`, `oc` und `kubectl` bereitstellen
- RHCOS Kernel, initramfs und rootfs herunterladen
- `openshift.conf` erzeugen bzw. eine bestehende Datei übernehmen
- Manifeste und Ignition-Dateien erzeugen
- RHCOS/Ignition über TFTP bzw. nginx bereitstellen
- `openshift.cfg` installieren
- `pxe-update` ausführen

Die Konfiguration liegt unter:

```text
/srv/tftp/config/openshift.conf
```

Beispiel für drei Control-Plane-Rechner:

```bash
HOSTS=(
    "*|ubuntu|"
    "80:EE:73:EF:0D:E9|openshift|master"
    "80:EE:73:EF:03:B3|openshift|master"
    "80:EE:73:EF:01:81|openshift|master"
)
```

## HAProxy Add-on

HAProxy bleibt vollständig getrennt vom PXE- und nginx-Setup:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-haproxy.sh | bash -
```

Das Script liest `/srv/tftp/config/openshift.conf` und richtet die OpenShift API (`6443`) sowie den Machine Config Server (`22623`) ein. nginx bleibt auf Port 80.

## Bestehende Lösung erweitern

### Neuer Ubuntu-basierter Stack

Beispiel `kurs1`:

1. Autoinstall-Datei bereitstellen:

```text
/var/www/html/autoinstall/user-data-kurs1
```

2. Stack anlegen:

```bash
sudo tee /srv/tftp/grub/stacks/kurs1.cfg >/dev/null <<'EOF_STACK'
set userdata="user-data-kurs1"
source (tftp,${tftp_server})/grub/stacks/_ubuntu-install.cfg
EOF_STACK
```

3. In `rack.conf` verwenden:

```bash
HOSTS=(
    "*|kurs1|"
)
```

4. Aktivieren:

```bash
sudo /srv/tftp/bin/pxe-update
```

### Neuer eigenständiger Stack

Ein Stack braucht nur eine Datei:

```text
/srv/tftp/grub/stacks/<name>.cfg
```

Beispiel:

```grub
menuentry "Mein System" {
    linux /linux/meinsystem/vmlinuz ...
    initrd /linux/meinsystem/initrd
}
```

Die dazu benötigten Images werden durch ein eigenes `install-<name>.sh` vollständig heruntergeladen und unter TFTP/HTTP abgelegt. Es braucht keine Änderung an `grub.cfg`, `pxe-update` oder `pxe-show`.

Danach reicht:

```bash
HOSTS=(
    "*|meinsystem|"
)
```

und:

```bash
sudo /srv/tftp/bin/pxe-update
```
