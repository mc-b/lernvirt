# SUSE / openSUSE PXE Stack

Der SUSE-Stack ergänzt die gemeinsame PXE-Basis aus [README.md](README.md). Der aktuelle Standardpfad installiert **openSUSE Leap** und richtet nach dem ersten lokalen Boot automatisch **RKE2, Helm, cert-manager und Rancher** ein.

## Installation

Auf einem bereits eingerichteten PXE-Server:

```bash
sudo ./install-suse.sh
```

Danach wird der Stack in `/srv/tftp/config/rack.conf` zugewiesen:

```bash
HOSTS=(
  "AA:BB:CC:DD:EE:FF|suse|"
)
```

und aktiviert:

```bash
sudo pxe-update
```

## Standardwerte

```bash
SUSE_VERSION=15.6
SUSE_ARCH=x86_64
SUSE_HOSTNAME=suse-rke2
SUSE_ROOT_PASSWORD=insecure
SUSE_AUTOYAST=suse-rke2.xml
RKE2_CHANNEL=stable
RKE2_METHOD=tar
HELM_VERSION=v3.22.0
CERT_MANAGER_VERSION=v1.21.2
RANCHER_VERSION=2.15.2
SSH_KEY_FILE=/etc/lernvirt/lerncloud.pub
```

Unterstützte Architekturen sind `x86_64` und `aarch64`. Für openSUSE Leap 15.x wird standardmässig das offizielle Installationsmedium verwendet. Für andere Versionen muss `SUSE_ISO` oder `SUSE_ISO_URL` explizit gesetzt werden.

## Installationsablauf

1. UEFI PXE lädt den SUSE-Stack.
2. Kernel und Initramfs werden per TFTP geladen.
3. Das Installationsmedium und AutoYaST werden über HTTP bereitgestellt.
4. openSUSE wird unattended installiert.
5. Der Installationsmarker wird gesetzt und der Rechner startet lokal.
6. `lernvirt-rke2-bootstrap.service` installiert RKE2, Helm, cert-manager und Rancher.

RKE2 verwendet standardmässig `canal` als CNI. Die kubeconfig liegt unter:

```text
/etc/rancher/rke2/rke2.yaml
```

## Rancher

Ohne explizites `RANCHER_HOST` wird als Hostname automatisch die Node-IP mit `sslip.io` verwendet.

Beispiel mit eigener Vorgabe:

```bash
sudo RANCHER_HOST=rancher.example.org ./install-suse.sh
```

Die erzeugten Zugangsinformationen werden nach dem Bootstrap auf dem Node gespeichert:

```bash
sudo cat /root/rancher-access.txt
```

Die Datei besitzt restriktive Rechte (`0600`).

## RKE2-Installationsmethode

Standard:

```bash
RKE2_METHOD=tar
```

Alternativ:

```bash
sudo RKE2_METHOD=rpm ./install-suse.sh
```

Eine feste RKE2-Version kann mit `RKE2_VERSION` vorgegeben werden; sonst wird der konfigurierte Channel verwendet.

## AutoYaST-Variante

Ohne `VARIANT` verwendet der Stack das generierte Standardprofil `suse-rke2.xml`.

Eine Host-Regel mit `VARIANT` wählt stattdessen ein eigenes AutoYaST-Profil:

```bash
HOSTS=(
  "AA:BB:CC:DD:EE:FF|suse|mein-autoyast.xml"
)
```

## Status nach der Installation

```bash
sudo systemctl status lernvirt-rke2-bootstrap --no-pager
sudo journalctl -u lernvirt-rke2-bootstrap -f

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes -o wide
helm list -A
sudo cat /root/rancher-access.txt
```

## Installationsmarker

AutoYaST legt `/boot/lernvirt-installed` an. Ist die EFI-Systempartition gemountet, wird zusätzlich `/boot/efi/lernvirt-installed` angelegt. Dadurch wechselt die allgemeine GRUB-Logik nach erfolgreicher Installation auf lokalen Boot.
