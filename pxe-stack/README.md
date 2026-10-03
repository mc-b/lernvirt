# lernvirt PXE Stack

`pxe-stack` stellt die PXE-Basis für lernvirt bereit und ordnet Rechnern über eine zentrale `rack.conf` einen Boot-/Installations-Stack zu.

Ein **Stack** ist eine GRUB-Bootdefinition. Beispiele:
- `ubuntu` – Ubuntu Server Autoinstall mit `user-data`
- `cna` – Ubuntu mit `user-data-cna` - Cloud-native
- `cna-full` – Ubuntu mit `user-data-cna-full` - Cloud-native
- `reset` – Ubuntu mit `user-data-reset`, um Rechner auf den Ausgangszustand zurückzusetzen
- `suse` – wird durch `install-suse.sh` ergänzt
- `harvester` – wird durch `install-harvester.sh` ergänzt
- `openshift` – wird durch `install-openshift.sh` ergänzt
Die PXE-Basis verwendet `dnsmasq` als Proxy-DHCP/TFTP, GRUB UEFI und `nginx` auf Port 80. Ubuntu wird für amd64 und arm64 vorbereitet. Alpine/BusyBox sind optionale Boot-Tools und keine Installationsstacks.
## Installation / cloud-init

Direkt:

    curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -

In cloud-init:

    #cloud-config
    runcmd:
      - curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=ubuntu bash -

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

`pxe-update` setzt `rack.conf` in die von GRUB verwendeten `runtime.cfg` und `hosts.cfg` um. Wenn der Harvester-Stack installiert ist, erzeugt es zusätzlich die node-spezifischen Harvester-Konfigurationen unter `/var/www/html/harvester/config/`.

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
User    : root
Password: keines
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
## Harvester Add-on

Harvester wird vollständig separat auf der bestehenden PXE-Basis eingerichtet:

```bash
sudo HARVESTER_VIP=192.168.1.110 ./install-harvester.sh
```

`HARVESTER_VIP` ist die freie statische Management-VIP des Harvester-Clusters. Die übrigen Standardwerte werden aus der bestehenden PXE-Konfiguration übernommen bzw. automatisch erzeugt. Insbesondere erzeugt `install-harvester.sh` beim ersten Aufruf einen Cluster-Token und ein OS-Passwort und speichert beides zentral in `/srv/tftp/config/rack.conf`. Für Lern-/Testsysteme wird standardmässig `HARVESTER_SKIPCHECKS=true` gesetzt, damit nicht erfüllte Production-Hardwarechecks nur Warnungen erzeugen und die automatische Installation nicht stoppen.

Standard ist Harvester `1.8.2` für `amd64`. Der Installer lädt ISO, Kernel, initrd und rootfs direkt aus dem offiziellen Harvester-Release, prüft das ISO per SHA512 und installiert den Stack `harvester`.

Das bestehende `MAC|STACK|VARIANT`-Format bleibt unverändert. Für Harvester enthält `VARIANT` den Installationsmodus und den Hostnamen:

```bash
HOSTS=(
    "*|ubuntu|"
    "AA:BB:CC:DD:EE:01|harvester|create:harvester-01"
    "AA:BB:CC:DD:EE:02|harvester|join:harvester-02"
    "AA:BB:CC:DD:EE:03|harvester|join:harvester-03"
)
```

Harvester benötigt eine explizite MAC-Adresse; `*|harvester|...` ist nicht zulässig. Nach einer Änderung an `HOSTS` reicht:

```bash
sudo /srv/tftp/bin/pxe-update
sudo /srv/tftp/bin/pxe-show
```

`pxe-update` erzeugt automatisch pro Harvester-Node eine YAML-Datei unter:

```text
/var/www/html/harvester/config/<mac>.yaml
```

Es muss keine `node1.yaml`, `node2.yaml` usw. manuell erstellt werden. Für `create:<hostname>` werden VIP und `vip_mode: static` gesetzt; für `join:<hostname>` wird automatisch `server_url: https://<HARVESTER_VIP>:443` gesetzt. Alle Nodes erhalten denselben Cluster-Token, die konfigurierte Installationsdisk, den SSH-Key und die PXE-MAC als Management-Interface. `pxe-update` schreibt zudem `install.skipchecks` gemäss `HARVESTER_SKIPCHECKS` in jede Node-Konfiguration.

Das Management-Interface heisst standardmässig `mgmt0`. Beim PXE-Boot wird die tatsächliche PXE-MAC mittels Kernelparameter `ifname=mgmt0:<MAC>` an diesen Namen gebunden, sodass kein hardwarespezifischer Interface-Name in einer Node-YAML gepflegt werden muss.

Harvester v1.8 verlangt für neue PXE-Installationen UEFI. Nach erfolgreicher Installation erkennt PXE-GRUB den Harvester-Datenträger über `COS_STATE` und bootet lokal. Die `COS_STATE`-Erkennung gilt nur, solange der Rechner in `rack.conf` weiterhin dem Stack `harvester` zugeordnet ist.

Weitere Details stehen in `HARVESTER.md`.
## OpenShift Add-on

OpenShift/RHCOS wird separat auf der bestehenden PXE-Basis eingerichtet:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-openshift.sh | bash -
```

Vorher muss das Red-Hat-Pull-Secret vorhanden sein:

```text
/etc/lernvirt/pull-secret.json
```

`install-openshift.sh` übernimmt den vollständigen Ablauf der bisherigen OpenShift-Lösung und integriert ihn in `pxe-stack`:
- `openshift-install`, `oc` und `kubectl` bereitstellen
- `br0` für die Bootstrap-VM erzeugen bzw. wiederverwenden
- OpenShift-DNS als separate dnsmasq-Add-on-Datei aktivieren
- **nginx nicht verändern**; RHCOS und Ignition werden über die bestehende `pxe-stack`-Site auf Port 80 ausgeliefert
- `machineNetwork` setzen und bei drei Control-Plane-Nodes `mastersSchedulable: true` aktivieren
- Bootstrap-Ignition mit statischem LAN, SSH-Key und Konsolenpasswort erweitern
- RHCOS PXE- und QEMU-Images laden
- für `terra2` bis `terra4` node-spezifische RHCOS-initramfs mit NetworkManager-Konfiguration und Post-Install-Marker erzeugen
- die drei MAC-Adressen automatisch in `rack.conf` als `openshift|terra2`, `openshift|terra3` und `openshift|terra4` eintragen
- temporäre Bootstrap-VM starten
- HAProxy für API `6443` und MCS `22623` aktivieren
- Nodes per Wake-on-LAN starten
- auf `bootstrap-complete` warten
- Bootstrap-VM entfernen
- Ingress-HAProxy auf `80/443` aktivieren
- auf `install-complete` warten
- `openshift-status` installieren
Die Konfiguration liegt unter:

```text
/srv/tftp/config/openshift.conf
```

Die Standardadressen sind:

```text
terra1 / API-LB       192.168.1.101
terra2                192.168.1.102
terra3                192.168.1.103
terra4                192.168.1.104
bootstrap             192.168.1.105
Ingress-LB final      192.168.1.105
```
Die Bootstrap-IP wird nach `bootstrap-complete` wiederverwendet. Der Ingress-HAProxy läuft dazu in einem eigenen Linux Network Namespace. Dadurch können OpenShift-Routes auf `80/443` bereitgestellt werden, obwohl nginx auf `terra1:80` unverändert weiterläuft.

Diagnose:

```bash
sudo openshift-status
sudo tail -f /var/log/openshift-install.log
```
Wenn `openshift-install wait-for bootstrap-complete` oder `wait-for install-complete`
in ein Timeout läuft, den Installer **nicht nochmals als neue Installation** starten.
Die vorhandenen Ignition-/PKI-Artefakte werden mit dem Resume-Modus weiterverwendet:

```bash
cd /srv/tftp
sudo ./install-openshift.sh resume
```
Ein normaler erneuter Aufruf von `install-openshift.sh` verweigert den Start, sobald
bereits Cluster-Artefakte existieren. Ein echter Neuaufbau muss explizit mit
`OCP_FORCE=1` angefordert werden.
### `oc` und `KUBECONFIG`

Die vom Installer erzeugte `system:admin`-Kubeconfig liegt unter:

```text
/opt/openshift/install/auth/kubeconfig
```

Sie ist standardmässig nur für root lesbar. Für administrative `oc`-Befehle:

```bash
sudo -i
export KUBECONFIG=/opt/openshift/install/auth/kubeconfig
oc get nodes
oc get co
```

Die Variable gilt für die aktuelle Shell. Soll sie in einer neuen root-Shell wieder
verwendet werden, muss `export KUBECONFIG=...` dort erneut gesetzt werden.
### OpenShift Console

Nach `Install complete!` ist die Web-Konsole unter folgender Adresse erreichbar:

```text
https://console-openshift-console.apps.ocp.lernvirt.test
```

Das initiale `kubeadmin`-Passwort steht in:

```bash
sudo cat /opt/openshift/install/auth/kubeadmin-password
```

Der Browser muss `*.apps.ocp.lernvirt.test` auf die Ingress-IP auflösen können
(Standard: `192.168.1.105`). Der pxe-stack-dnsmasq liefert diesen Wildcard-DNS-Eintrag.
## HAProxy Add-on

`install-haproxy.sh` wird vom OpenShift-Installer automatisch in zwei Phasen verwendet. Es kann auch manuell ausgeführt werden:

```bash
sudo ./install-haproxy.sh bootstrap
sudo ./install-haproxy.sh final
```
`bootstrap` stellt API `6443` und MCS `22623` auf `terra1` für Bootstrap und Control Plane bereit. `final` entfernt Bootstrap aus diesen Backends und startet zusätzlich den Ingress-HAProxy auf `80/443` im Network Namespace. Die nginx-Konfiguration wird in beiden Phasen nicht verändert.
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

Ein Stack braucht grundsätzlich nur eine Datei:

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

Die dazu benötigten Images werden durch ein eigenes `install-<name>.sh` vollständig heruntergeladen und unter TFTP/HTTP abgelegt. Für einfache eigenständige Stacks braucht es keine Änderung an `grub.cfg`, `pxe-update` oder `pxe-show`. Harvester ist eine Ausnahme, weil `pxe-update` die node-spezifischen unattended-Konfigurationen aus `rack.conf` erzeugt und `grub.cfg` den lokalen Harvester-Datenträger erkennen muss.

Danach reicht bei einfachen Stacks:

```bash
HOSTS=(
    "*|meinsystem|"
)
```

und:

```bash
sudo /srv/tftp/bin/pxe-update
```
## OpenShift und dnsmasq

Der PXE-Basisbetrieb verwendet `port=0` in `/etc/dnsmasq.d/pxe.conf`, weil dnsmasq dort nur Proxy-DHCP/TFTP bereitstellt. `install-openshift.sh` schaltet diese bestehende Einstellung auf `port=53` um und ergänzt die OpenShift-DNS-Records in `/etc/dnsmasq.d/zz-openshift.conf`. Die Option `port` wird bewusst nur einmal definiert. nginx wird durch die OpenShift-Installation nicht verändert.
### RHCOS: zweiter PXE-Boot

Nach erfolgreicher RHCOS-Installation erkennt PXE-GRUB den Marker auf der separaten `boot`-Partition und chainloadet den lokal installierten Red-Hat-EFI-Bootloader direkt. Dadurch ist kein Firmware-Fallback via `exit` nötig. Für bereits installierte pxe-stack-Versionen kann der lokale Bootpfad einmalig mit `sudo /srv/tftp/bin/pxe-fix-rhcos-localboot` aktualisiert werden.
