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

Das Script erzeugt `/srv/tftp/grub/stacks/openshift-sno.cfg` selbst. Es darf deshalb auch ausgefuehrt werden, bevor ein `openshift-sno`-Eintrag in `rack.conf` existiert. Ist der Eintrag bereits vorhanden, wird die MAC-Adresse automatisch uebernommen.

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

`pxe-update` immer mit `sudo` ausfuehren, da es Dateien unter `/srv/tftp/grub` erzeugt.

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

## Hinweis zu `oc`

`openshift-install agent create pxe-files` ruft intern den `oc`-Client auf. Das Installationsscript installiert deshalb `oc` zusammen mit `openshift-install` nach `/opt/openshift-sno/bin` und nimmt dieses Verzeichnis fuer den gesamten Lauf in `PATH` auf.



## Netzwerk fuer dieses Lab

Der SNO-Knoten soll fest `10.31.20.15` verwenden. Deshalb ist die Beispielkonfiguration nun statisch:

```bash
SNO_NETWORK_MODE="static"
SNO_INTERFACE="enp2s0"
SNO_PREFIX="24"
SNO_GATEWAY="auto"
SNO_DNS="10.31.20.11"
```

`SNO_MAC` wird aus `rack.conf` erkannt, wenn genau ein Host dem Stack `openshift-sno` zugeordnet ist. `SNO_GATEWAY="auto"` uebernimmt das IPv4-Default-Gateway des PXE-Servers.

Wenn bereits PXE-Artefakte mit DHCP erzeugt wurden, muss die Konfiguration neu erzeugt werden:

```bash
sudo OCP_FORCE=1 ./install-openshift-sno.sh
```

Beim Boot muss der Agent danach `10.31.20.15` anzeigen. Wenn dort eine andere Adresse steht und gleichzeitig `The rendezvous host is at 10.31.20.15` erscheint, ist die Netzwerkkonfiguration noch falsch.

RHCOS hat kein Root-Passwort fuer die Konsolenanmeldung. Fuer Diagnose per SSH wird der in `SSH_KEY_FILE` hinterlegte Public Key verwendet; die Anmeldung erfolgt als Benutzer `core` mit dem passenden privaten Key.
