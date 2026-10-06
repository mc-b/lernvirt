# OpenShift PXE Stack

Der OpenShift-Stack installiert einen OpenShift-Cluster mit RHCOS-Nodes über die gemeinsame PXE-Basis aus [README.md](README.md). Die OpenShift-spezifische Konfiguration liegt getrennt unter `/srv/tftp/config/openshift.conf`.

## Voraussetzungen

Die PXE-Basis muss bereits eingerichtet sein. Zusätzlich wird ein gültiges Red-Hat-Pull-Secret benötigt:

```text
/etc/lernvirt/pull-secret.json
```

Die vorkonfigurierten Nodes müssen per UEFI PXE booten können. Der Installer richtet zusätzlich libvirt, HAProxy, DNS-Einträge und die für RHCOS benötigten PXE-Artefakte ein.

## Installation

Neue Installation:

```bash
sudo ./install-openshift.sh
```

Fortsetzen einer bereits gestarteten Installation:

```bash
sudo ./install-openshift.sh resume
```

Eine neue Installation trotz vorhandener Artefakte kann explizit erzwungen werden:

```bash
sudo OCP_FORCE=1 ./install-openshift.sh
```

Bei einem Timeout während Bootstrap oder Cluster-Installation sollte `resume` verwendet werden. Dadurch bleiben vorhandene Ignition-Dateien, PKI und Cluster-Identität erhalten.

## Standardkonfiguration

Beim ersten Lauf wird `/srv/tftp/config/openshift.conf` erzeugt. Wichtige Standardwerte sind:

```bash
OCP_CHANNEL=stable-4.20
CLUSTER_NAME=ocp
BASE_DOMAIN=lernvirt.test
MACHINE_NETWORK_CIDR=192.168.1.0/24
INSTALL_DISK=/dev/nvme0n1
CORE_PASSWORD=insecure
```

Der PXE-Server ist standardmässig `terra1`. Die Nodes `terra2` bis `terra4` sowie eine temporäre Bootstrap-VM werden über die OpenShift-Konfiguration adressiert.

## Andere Cluster-Domain verwenden

Die Domain sollte bei einer **neuen** Installation festgelegt werden:

```bash
sudo CLUSTER_NAME=ocp \
     BASE_DOMAIN=hf01.lernvirt.test \
     ./install-openshift.sh
```

Daraus entstehen beispielsweise:

```text
api.ocp.hf01.lernvirt.test
*.apps.ocp.hf01.lernvirt.test
https://console-openshift-console.apps.ocp.hf01.lernvirt.test
```

Existiert `/srv/tftp/config/openshift.conf` bereits, muss die Konfiguration vor einer neuen Installation dort angepasst werden. Bei `resume` darf die Cluster-Identität bzw. Domain nicht nachträglich geändert werden.

## Ablauf

Der Installer führt im Wesentlichen folgende Schritte aus:

1. Netzwerk-Bridge und OpenShift-DNS vorbereiten.
2. `openshift-install`, `oc` und RHCOS-Artefakte laden.
3. `install-config.yaml` und Ignition-Dateien erzeugen.
4. PXE-Konfiguration für die RHCOS-Nodes bereitstellen.
5. OpenShift-Host-Regeln in die PXE-Konfiguration integrieren.
6. HAProxy für die Bootstrap-Phase einrichten.
7. Temporäre Bootstrap-VM mit libvirt starten.
8. Physische Nodes starten bzw. per Wake-on-LAN aktivieren.
9. Auf `bootstrap-complete` warten.
10. Bootstrap-VM entfernen und HAProxy auf den finalen Cluster umstellen.
11. Auf `install-complete` warten.

Die RHCOS-Initramfs der einzelnen Nodes enthalten ihre jeweilige Netzwerkkonfiguration.

## HAProxy und Ingress

Während der Bootstrap-Phase stellt HAProxy die OpenShift-Endpunkte inklusive API bereit. Nach erfolgreichem Bootstrap wird die temporäre Bootstrap-IP als finale Ingress-IP weiterverwendet.

Die finale Weiterleitung von Port 80/443 läuft in einem eigenen Linux-Network-Namespace. Dadurch kann nginx auf dem PXE-Server weiterhin Port 80 verwenden.

Der HAProxy-Schritt kann bei Bedarf separat ausgeführt werden:

```bash
sudo ./install-haproxy.sh bootstrap
sudo ./install-haproxy.sh final
```

## DNS / dnsmasq

Die PXE-Basis betreibt `dnsmasq` normalerweise nur für Proxy-DHCP/TFTP mit `port=0`. Der OpenShift-Installer aktiviert zusätzlich DNS und legt die OpenShift-spezifischen Einträge in einer separaten dnsmasq-Konfiguration ab.

Damit werden unter anderem die API- und Apps-Namen des Clusters im Installationsnetz aufgelöst.

## Status und Zugriff

Status:

```bash
sudo openshift-status
```

Installationslog:

```bash
tail -f /var/log/openshift-install.log
```

Kubeconfig setzen:

```bash
export KUBECONFIG=/opt/openshift/install/auth/kubeconfig
oc get nodes
```

Initiales `kubeadmin`-Passwort:

```bash
cat /opt/openshift/install/auth/kubeadmin-password
```

Console bei den Standardwerten:

```text
https://console-openshift-console.apps.ocp.lernvirt.test
```

RHCOS verwendet den Benutzer `core`. Das während der Installation gesetzte Passwort stammt aus `CORE_PASSWORD` in `openshift.conf`.

## Lokaler Boot nach der Installation

RHCOS verwendet eine separate Boot-Partition. Die GRUB-Logik der PXE-Basis erkennt deshalb neben `/boot/lernvirt-installed` auch `/lernvirt-installed` und chainloadet anschliessend den Red-Hat-EFI-Bootloader der lokalen Installation.
