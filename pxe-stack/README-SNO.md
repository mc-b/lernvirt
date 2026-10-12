# OpenShift Single Node (SNO) fuer pxe-stack

Der Add-on-Stack installiert OpenShift 4.20 als **Single Node OpenShift** mit dem Agent-based Installer.

Voreinstellung:

```text
PXE/DNS : 10.31.20.11
SNO     : 10.31.20.15
Cluster : ocp.lernvirt.test
```

Es gibt **keine separate Bootstrap-VM und keinen HAProxy**. nginx wird nicht veraendert. Der Agent-based Installer erzeugt die PXE-Artefakte; `rack.conf` entscheidet wie bei SUSE, welcher Rechner den Stack bootet.

## Vorbereitung

Pull Secret:

```text
/etc/lernvirt/pull-secret.json
```

SSH Public Key:

```text
/etc/lernvirt/lerncloud.pub
```

Dann einmalig:

```bash
sudo ./install-openshift-sno.sh
```

Die Konfiguration wird beim ersten Lauf angelegt unter:

```text
/srv/tftp/config/openshift-sno.conf
```

Standard ist DHCP. Der Zielrechner muss dabei `10.31.20.15` erhalten. Der PXE-Boot verwendet `10.31.20.11` als DNS; fuer den laufenden Cluster muss dieser DNS oder ein anderer DNS die OpenShift-Namen ebenfalls aufloesen.

## rack.conf

Nach der Vorbereitung nur den Zielrechner zuordnen:

```bash
HOSTS=(
    "*|cna|"
    "AA:BB:CC:DD:EE:FF|openshift-sno|"
)
```

Danach:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

Nun den Zielserver per PXE booten. Nach erfolgreicher Installation erkennt `openshift-sno.cfg` den lokalen RHCOS-EFI-Bootloader und bootet beim naechsten PXE-Start lokal statt erneut zu installieren.

## Installation beobachten

```bash
sudo /srv/tftp/bin/openshift-sno-wait bootstrap
sudo /srv/tftp/bin/openshift-sno-wait install
```

Status:

```bash
sudo /srv/tftp/bin/openshift-sno-wait status
```

Nach `Install complete!`:

```bash
sudo -i
export KUBECONFIG=/opt/openshift-sno/install/auth/kubeconfig
/opt/openshift-sno/bin/oc get nodes
/opt/openshift-sno/bin/oc get co
```

Console:

```text
https://console-openshift-console.apps.ocp.lernvirt.test
```

Kubeadmin-Passwort:

```bash
sudo cat /opt/openshift-sno/install/auth/kubeadmin-password
```

## Statisches Netzwerk (optional)

Falls DHCP nicht verwendet werden soll, in `/srv/tftp/config/openshift-sno.conf` setzen:

```bash
SNO_NETWORK_MODE="static"
SNO_INTERFACE="eno1"
SNO_MAC="AA:BB:CC:DD:EE:FF"
SNO_PREFIX="24"
SNO_GATEWAY="10.31.20.1"
SNO_DNS="10.31.20.11"
```

Bei geaenderter Cluster-/Netzwerkkonfiguration werden vorhandene PKI-/Agent-Artefakte aus Sicherheitsgruenden nicht stillschweigend ersetzt. Fuer eine bewusste Neuinstallation:

```bash
sudo OCP_FORCE=1 ./install-openshift-sno.sh
```
