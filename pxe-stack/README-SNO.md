# OpenShift SNO fuer lernvirt pxe-stack

Der PXE-Server stellt nur gemeinsame **RHCOS Images, OpenShift Installer und Scripts** bereit. Es gibt keine clusterbezogenen Installer-Verzeichnisse auf dem PXE-Server, kein HAProxy, keine Bootstrap-VM und kein zweites Finish-Script.

## 1. PXE-Server einmalig vorbereiten

Voraussetzungen:

```text
/srv/tftp/config/rack.conf
/etc/lernvirt/pull-secret.json
/etc/lernvirt/lerncloud.pub
```

Installation:

```bash
sudo ./install-openshift-sno.sh
```

Beim ersten Lauf wird erzeugt:

```text
/srv/tftp/config/openshift-sno.conf
```

Beispiel fuer das aktuelle Lab:

```bash
OCP_CHANNEL="stable-4.20"
BASE_DOMAIN="lernvirt.test"
MACHINE_NETWORK_CIDR="10.31.20.0/24"
INSTALL_DISK="/dev/nvme0n1"
DNS_SERVER="10.31.20.11"
```

`install-openshift-sno.sh` laedt den passenden OpenShift Installer und bestimmt damit automatisch die passende RHCOS-PXE-Version (`openshift-install coreos print-stream-json`). nginx wird nicht veraendert.

## 2. SNO in rack.conf zuordnen

Das dritte Feld ist der OpenShift-Clustername:

```bash
HOSTS=(
    "*|ubuntu|"
    "80:ee:73:ef:0d:e9|openshift-sno|hf01"
    "80:ee:73:ef:03:b3|openshift-sno|hf02"
)
```

Aktivieren:

```bash
sudo /srv/tftp/bin/pxe-update
```

Danach PXE-Boot des Zielsystems. Es ist kein weiterer Befehl auf dem PXE-Server erforderlich.

## 3. Netzwerk und lokale Namensaufloesung

Die erste RHCOS-Live-Phase verwendet DHCP. Jeder SNO sollte deshalb eine DHCP-Reservation besitzen. Die erhaltene Adresse wird vom Zielsystem als statische Konfiguration fuer Bootstrap und installiertes RHCOS uebernommen.

Der Zielserver erzeugt lokal unter `/etc/hosts` mindestens:

```text
10.31.20.25 sno-terra5 sno-terra5.terra5.lernvirt.test
10.31.20.25 api.terra5.lernvirt.test
10.31.20.25 api-int.terra5.lernvirt.test
10.31.20.25 console-openshift-console.apps.terra5.lernvirt.test
10.31.20.25 oauth-openshift.apps.terra5.lernvirt.test
10.31.20.25 downloads-openshift-console.apps.terra5.lernvirt.test
10.31.20.25 canary-openshift-ingress-canary.apps.terra5.lernvirt.test
```

Da das Lab IPv4-only ist, wird `localhost` nur auf `127.0.0.1` gelegt; `::1` bekommt nur die `localhost6`-Namen. Dadurch greifen OpenShift-Komponenten mit `https://localhost:6443` nicht versehentlich auf IPv6 zu, waehrend der API-Server auf `tcp4` gebunden ist.

`/etc/hosts` kann keine Wildcards. Beliebige spaetere Routes unter `*.apps.<cluster>.<baseDomain>` benoetigen fuer externe Clients weiterhin DNS oder explizite Host-Eintraege.

## 4. Persistenz nach dem Disk-Reboot

Die fuer den SNO kritischen Dateien werden nicht nur in die Live-Ignition geschrieben:

- `/etc/hostname` und `/etc/hosts` werden als Day-1 `MachineConfig` in die OpenShift-Manifeste aufgenommen.
- Vor `install-to-disk.service` wird die von Bootstrap-in-Place erzeugte `/opt/openshift/master.ign` nochmals erweitert.
- Dadurch bleiben Hostname, Hosts-Datei, Admin-kubeconfig und kubeadmin-Passwort nach dem Disk-Reboot erhalten.

Persistiert werden:

```text
/etc/hostname
/etc/hosts
/root/.kube/config
/root/kubeadmin-password
/var/lib/lernvirt/cluster.env
/etc/profile.d/lernvirt-openshift.sh
```

`/usr/local/bin/oc` wird nicht veraendert. RHCOS/OpenShift stellt den Client selbst als `/bin/oc` bereit.

## 5. Ablauf auf dem Zielserver

```text
PXE/RHCOS Live
 -> Clustername aus rack.conf VARIANT
 -> IP / Interface / Gateway / DNS erkennen
 -> Hostname sno-<cluster> setzen
 -> lokale OpenShift-Namen in /etc/hosts
 -> install-config.yaml erzeugen
 -> openshift-install create manifests
 -> persistente Day-1 MachineConfig fuer Hostname/Hosts einfuegen
 -> openshift-install create single-node-ignition-config
 -> finale master.ign vor install-to-disk ergaenzen
 -> statische Netzkonfiguration in das RHCOS-PXE-initramfs
 -> kexec in die Bootstrap-in-Place-Phase
 -> OpenShift bootstrappt sich selbst
 -> RHCOS wird auf INSTALL_DISK geschrieben
 -> Reboot von lokaler Disk
```

## 6. Zugriff nach der Installation

```bash
ssh core@10.31.20.25
sudo -i
oc get nodes
oc get co
cat /root/kubeadmin-password
```

Beim Root-Login wird automatisch gesetzt:

```bash
KUBECONFIG=/root/.kube/config
```

Console fuer `terra5`:

```text
https://console-openshift-console.apps.terra5.lernvirt.test
```

## 7. Fehlerdiagnose waehrend der Installation

Erste PXE-Phase:

```bash
sudo journalctl -u lernvirt-openshift-sno.service -f
```

Bootstrap-in-Place:

```bash
sudo journalctl -b -f -u bootkube.service -u install-to-disk.service
```

Nach dem Disk-Reboot:

```bash
sudo journalctl -b -f -u bootkube.service
```

## Korrekturen in v4

- Hostname wird bereits in der Live-Phase gesetzt und persistent als `/etc/hostname` hinterlegt.
- `/etc/hosts` wird persistent als Day-1 MachineConfig erzeugt.
- Die finale `/opt/openshift/master.ign` wird vor `install-to-disk.service` erweitert; damit gehen die lernvirt-Dateien beim Bootstrap-in-Place-Uebergang nicht verloren.
- Das eigene `oc`-Download-/Wrapper-Konstrukt wurde entfernt; verwendet wird das native `/bin/oc`.
- Der fruehere Literal-`\\n`-Fehler in Profile-/Hilfsdateien ist nicht mehr enthalten.
- IPv4-only `localhost` verhindert den beobachteten Zugriff auf `[::1]:6443`.

## Sicherheit

Pull Secret und OpenShift Installer werden im internen PXE-Netz per HTTP bereitgestellt. Das PXE-Netz muss daher als vertrauenswuerdig behandelt werden.
