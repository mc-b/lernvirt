# OpenShift SNO fuer lernvirt pxe-stack

Der PXE-Server stellt nur gemeinsame **RHCOS Images, OpenShift Binaries und Scripts** bereit. Es gibt keine clusterbezogenen Installer-Verzeichnisse, keine kubeconfig auf dem PXE-Server, kein HAProxy, keine Bootstrap-VM und kein `openshift-sno-wait`.

## 1. PXE-Server einmalig vorbereiten

Voraussetzungen wie beim bestehenden `pxe-stack`:

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

Default fuer das aktuelle Lab:

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

## 3. DHCP/DNS

Die erste RHCOS-Live-Phase verwendet DHCP. Deshalb sollte jeder SNO eine DHCP-Reservation besitzen. Die dabei erhaltene Adresse wird vom Zielsystem automatisch als statische RHCOS-Konfiguration fuer die Installation uebernommen.

Fuer `hf01` mit `10.31.20.15` muessen vor dem Boot mindestens folgende DNS-Namen auf `10.31.20.15` zeigen:

```text
api.hf01.lernvirt.test
api-int.hf01.lernvirt.test
*.apps.hf01.lernvirt.test
```

Das Zielsystem prueft diese Records vor dem Erzeugen der SNO-Ignition. Damit wird vermieden, dass ein Cluster mit der falschen DHCP-Adresse bootstrappt.

## 4. Ablauf auf dem Zielserver

Der Vorgang laeuft ohne Bedienung:

```text
PXE/RHCOS Live
 -> Clustername aus rack.conf VARIANT lesen
 -> eigene IP / Interface / Gateway erkennen
 -> DNS pruefen
 -> install-config.yaml lokal in /run erzeugen
 -> openshift-install create single-node-ignition-config
 -> eigene kubeconfig + kubeadmin-password in die SNO-Ignition aufnehmen
 -> aktuelle Netzkonfiguration in das RHCOS-PXE-initramfs uebernehmen
 -> kexec in die clusterbezogene Bootstrap-in-Place-Phase
 -> OpenShift bootstrappt sich selbst
 -> RHCOS wird auf INSTALL_DISK geschrieben
 -> Reboot von lokaler Disk
```

Nach erfolgreicher Installation erkennt `openshift-sno.cfg` den lokalen RHCOS EFI-Bootloader und bootet beim naechsten PXE-Start standardmaessig von der lokalen Platte.

## 5. Zugriff auf dem installierten SNO

SSH erfolgt mit dem in `/etc/lernvirt/lerncloud.pub` hinterlegten Key:

```bash
ssh core@10.31.20.15
sudo -i
```

Die lokale Admin-kubeconfig liegt auf dem SNO unter:

```text
/root/.kube/config
```

Beim Root-Login wird `KUBECONFIG` automatisch darauf gesetzt. Der `oc` Client wird vom fertigen SNO einmalig vom PXE-Server nach `/var/lib/lernvirt/bin/oc` geladen; `/usr/local/bin/oc` ist ein Wrapper darauf.

Pruefung:

```bash
sudo -i
oc get nodes
oc get co
cat /root/kubeadmin-password
```

Console fuer `hf01`:

```text
https://console-openshift-console.apps.hf01.lernvirt.test
```

Fuer `hf02` entsprechend:

```text
https://console-openshift-console.apps.hf02.lernvirt.test
```

## 6. Fehlerdiagnose in der ersten PXE-Phase

Die generische Live-Ignition hinterlegt den SSH-Key fuer `core`. Solange die Maschine noch in der ersten RHCOS-Live-Phase ist:

```bash
ssh core@<dhcp-ip>
sudo journalctl -u lernvirt-openshift-sno.service -f
```

Auf der lokalen Konsole werden dieselben Meldungen ausgegeben.

## Sicherheit

Pull Secret, OpenShift Installer und Client werden im internen PXE-Netz per HTTP bereitgestellt. Das entspricht der bestehenden HTTP-PXE-Infrastruktur, bedeutet aber, dass das PXE-Netz als vertrauenswuerdig behandelt werden muss.
