# SUSE / openSUSE + RKE2 via lernvirt PXE

`install-suse.sh` richtet den Stack `suse` als vollständige, unbeaufsichtigte
Single-Node-Kubernetes-Installation ein.

## Ablauf

1. PXE bootet den openSUSE-Leap-Installer.
2. AutoYaST installiert openSUSE Leap auf `INSTALL_DISK` aus `rack.conf`.
3. `/boot/lernvirt-installed` wird vor dem ersten Reboot gesetzt.
4. Beim ersten lokalen Boot startet `lernvirt-rke2-bootstrap.service`.
5. Das Bootstrap-Script bereitet Wicked/NetworkManager und AppArmor vor,
   deaktiviert `firewalld` für den RKE2-Default-CNI Canal und installiert RKE2.
6. `rke2-server` wird gestartet.
7. Das Bootstrap wartet, bis der Kubernetes-Node `Ready` ist.

RKE2-Server-Nodes sind standardmässig schedulable. Für einen Lern-/Testcluster
reicht deshalb ein einzelner Server-Node.

## Installation auf dem PXE-Server

```bash
sudo ./install-suse.sh
```

Standardwerte:

```text
openSUSE Leap : 15.6
Architektur   : x86_64
Hostname      : suse-rke2
RKE2 Channel  : stable
RKE2 Methode  : tar
Zielplatte    : INSTALL_DISK aus /srv/tftp/config/rack.conf
```

In `rack.conf` genügt:

```bash
HOSTS=(
    "*|suse|"
)
```

Danach:

```bash
sudo /srv/tftp/bin/pxe-update
```

Die Default-AutoYaST-Datei liegt unter:

```text
/var/www/html/autoyast/suse-rke2.xml
```

## Overrides

Beispiel:

```bash
sudo \
  SUSE_HOSTNAME=rke2-node-01 \
  SUSE_ROOT_PASSWORD=insecure \
  RKE2_CHANNEL=stable \
  ./install-suse.sh
```

Eine konkrete RKE2-Version kann gepinnt werden:

```bash
sudo RKE2_VERSION='v1.35.5+rke2r2' ./install-suse.sh
```

Ein eigenes AutoYaST-Profil bleibt über die bestehende `VARIANT`-Logik möglich:

```bash
HOSTS=(
    "*|suse|mein-profil.xml"
)
```

Die Datei muss unter `/var/www/html/autoyast/mein-profil.xml` liegen.

## Status auf dem installierten Node

```bash
systemctl status lernvirt-rke2-bootstrap --no-pager
journalctl -u lernvirt-rke2-bootstrap -f
```

Nach erfolgreichem Bootstrap:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

Der von RKE2 mitgelieferte `kubectl` liegt unter:

```text
/var/lib/rancher/rke2/bin/kubectl
```

Das Bootstrap-Script legt zusätzlich `/usr/local/bin/kubectl` als Symlink an
und setzt `KUBECONFIG` über `/etc/profile.d/rke2.sh`.

## Remote-Kubeconfig

Für Zugriff von einem anderen Rechner:

```bash
scp root@<NODE-IP>:/etc/rancher/rke2/rke2.yaml ~/.kube/config
sed -i 's/127.0.0.1/<NODE-IP>/' ~/.kube/config
kubectl get nodes
```

Der Node-Hostname und seine primäre IPv4-Adresse werden beim ersten Start als
TLS-SAN in `/etc/rancher/rke2/config.yaml` aufgenommen.

## Diagnose

```bash
journalctl -u lernvirt-rke2-bootstrap -b --no-pager
journalctl -u rke2-server -b --no-pager -n 200
systemctl status rke2-server --no-pager -l
cat /etc/rancher/rke2/config.yaml
ip -br addr
ip route
```

Bootstrap-Log:

```text
/var/log/lernvirt-rke2-bootstrap.log
```

Erfolgsmarker:

```text
/var/lib/lernvirt/rke2-ready
```

### AutoYaST-Basisprodukt

Für openSUSE Leap 15.6 muss im AutoYaST-Profil das Basisprodukt `Leap` verwendet werden:

```xml
<products config:type="list">
  <product>Leap</product>
</products>
```

## AutoYaST und Local Boot

Das Profil verwendet `Leap` als Basisprodukt und das Standardmuster `enhanced_base`. RKE2-spezifische Zusatzpakete werden bewusst erst im installierten System installiert. Dadurch bleibt die AutoYaST-Paketauflösung auf dem Installationsmedium minimal und reproduzierbar.

Nach erfolgreicher Paketinstallation legt der Chroot-Schritt `/boot/lernvirt-installed` an. Bei UEFI wird zusätzlich `/boot/efi/lernvirt-installed` auf der EFI-Systempartition angelegt. PXE-GRUB findet damit den Marker auch unabhängig vom Btrfs-Subvolume-Layout. Bei einer abgebrochenen AutoYaST-Installation wird der Marker absichtlich nicht erzeugt.

### RKE2-Tar-Installer

Der Bootstrap installiert vor RKE2 explizit `tar` und `gzip` und prüft die vom offiziellen Tar-Installer benötigten Basiswerkzeuge. Ein bestehender Node kann nach einem früheren `tar: command not found` ohne Neuinstallation mit `zypper install tar gzip` und einem Neustart von `lernvirt-rke2-bootstrap.service` fortgesetzt werden.
