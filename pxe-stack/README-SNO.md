# OpenShift SNO für lernvirt pxe-stack

Dieses Add-on installiert **Single Node OpenShift (SNO)** über den bestehenden lernvirt `pxe-stack`.

Der PXE-Server stellt nur die gemeinsamen RHCOS-/Installer-Dateien bereit. Der Clustername kommt aus `rack.conf`; die Zielmaschine erzeugt ihre cluster-spezifische Installation selbst.

## Installation auf dem PXE-Server

Voraussetzungen:

```text
/etc/lernvirt/pull-secret.json
/etc/lernvirt/lerncloud.pub
```

Add-on installieren bzw. aktualisieren:

```bash
sudo ./install-openshift-sno.sh
```

Die globale Konfiguration liegt unter:

```text
/srv/tftp/config/openshift-sno.conf
```

Beispiel:

```bash
OCP_CHANNEL="stable-4.20"
BASE_DOMAIN="lernvirt.test"

MACHINE_NETWORK_CIDR="10.31.20.0/24"
CLUSTER_NETWORK_CIDR="10.128.0.0/14"
CLUSTER_HOST_PREFIX="23"
SERVICE_NETWORK_CIDR="172.30.0.0/16"

INSTALL_DISK="/dev/nvme0n1"
DNS_SERVER="10.31.20.11"

PULL_SECRET_FILE="/etc/lernvirt/pull-secret.json"
SSH_KEY_FILE="/etc/lernvirt/lerncloud.pub"
```

## SNO in `rack.conf` eintragen

Format:

```text
MAC|openshift-sno|CLUSTERNAME
```

Beispiel:

```bash
HOSTS=(
    "80:ee:73:ef:0d:e9|openshift-sno|terra5"
)
```

Aktivieren:

```bash
sudo /srv/tftp/bin/pxe-update
```

Beim nächsten PXE-Boot erscheint z.B.:

```text
Install OpenShift SNO terra5
```

Danach installiert sich die Maschine selbstständig.

## SSH auf die SNO-Maschine

Der in `SSH_KEY_FILE` konfigurierte Public Key wird für den Benutzer `core` verwendet.

Beispiel:

```bash
ssh -i ~/.ssh/lerncloud core@10.31.20.25
```

Root-Shell:

```bash
sudo -i
```

Hostname und Netzwerk prüfen:

```bash
hostnamectl
ip -4 addr show br-ex
ip route
```

## `oc` und `KUBECONFIG` auf der SNO-Maschine

`oc` ist in RHCOS bereits vorhanden:

Als root setzt `/etc/profile.d/lernvirt-openshift.sh` `KUBECONFIG` automatisch, sobald die Kubeconfig vorhanden ist.

Manuell:

```bash
sudo -i
export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
```

Prüfen:

```bash
echo "$KUBECONFIG"
oc whoami
oc get nodes -o wide
oc get co
```

Während des Bootstrap kann vorübergehend diese Kubeconfig notwendig sein:

```bash
export KUBECONFIG=/etc/kubernetes/bootstrap-secrets/kubeconfig
```

`/etc/kubernetes/bootstrap-secrets/` ist temporär und wird nach dem Bootstrap entfernt.

Nützliche Befehle:

```bash
oc get nodes -o wide
oc get co
oc get clusterversion
oc get pods -A
oc get events -A --sort-by=.lastTimestamp
```

## Installationsstatus

Bootstrap-in-Place:

```bash
systemctl status bootkube.service --no-pager
journalctl -b -u bootkube.service -f
```

Kubelet:

```bash
systemctl status kubelet.service --no-pager
journalctl -b -u kubelet.service -f
```

API testen:

```bash
curl -sk https://127.0.0.1:6443/readyz
```

ClusterOperatoren:

```bash
oc get co
```

Eine fertige Installation sollte bei allen ClusterOperatoren `AVAILABLE=True` und normalerweise `DEGRADED=False` zeigen.

## Web Console

Die Console-URL lautet:

```text
https://console-openshift-console.apps.<cluster>.<base-domain>
```

Beispiel für `terra5`:

```text
https://console-openshift-console.apps.terra5.lernvirt.test
```

Die aktuelle URL kann mit `oc` abgefragt werden:

```bash
oc whoami --show-console
```

### Namensauflösung auf dem Admin-PC

Die `/etc/hosts`-Einträge auf dem SNO gelten nur auf der SNO-Maschine. Der Browser-PC muss die OpenShift-Namen ebenfalls auf die SNO-IP auflösen können.

Für `terra5` mit `10.31.20.25` mindestens:

```text
10.31.20.25 api.terra5.lernvirt.test
10.31.20.25 console-openshift-console.apps.terra5.lernvirt.test
10.31.20.25 oauth-openshift.apps.terra5.lernvirt.test
```

Linux:

```text
/etc/hosts
```

Windows:

```text
C:\Windows\System32\drivers\etc\hosts
```

`hosts` kann keine Wildcards. Für beliebige OpenShift-Routes unter
`*.apps.<cluster>.<base-domain>` ist deshalb später ein DNS-Wildcard-Eintrag sinnvoll.

## Admin-Benutzer für CLI und Web Console

Für den dauerhaften Betrieb empfiehlt sich ein eigener OpenShift-Benutzer. Das folgende Beispiel erzeugt im Lab einen lokalen HTPasswd-Benutzer `admin` und gibt ihm `cluster-admin`.

Auf der SNO-Maschine als root:

```bash
sudo -i
export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
```

Passwort eingeben und HTPasswd-Datei erzeugen:

```bash
read -rsp 'Passwort für admin: ' PASSWORD; echo
printf 'admin:%s\n' "$(openssl passwd -apr1 "$PASSWORD")" > /tmp/users.htpasswd
unset PASSWORD
```

Secret erzeugen bzw. aktualisieren:

```bash
oc create secret generic htpass-secret \
  --from-file=htpasswd=/tmp/users.htpasswd \
  -n openshift-config \
  --dry-run=client -o yaml | oc apply -f -
```

Identity Provider konfigurieren:

```bash
cat <<'EOF_IDP' | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: lernvirt
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF_IDP
```

Cluster-Admin-Rechte vergeben:

```bash
oc adm policy add-cluster-role-to-user cluster-admin admin
```

Status prüfen:

```bash
oc get co authentication console ingress
```

Danach kann man sich an der Web Console mit Benutzer `admin` und dem gesetzten Passwort anmelden.

## `oc` auf einem Admin-PC

Auf dem Admin-PC müssen mindestens `api.<cluster>.<base-domain>` sowie die Console-/OAuth-Namen auflösbar sein.

Nach Einrichtung des Benutzers `admin`:

```bash
oc login https://api.terra5.lernvirt.test:6443 -u admin
```

Danach wird die lokale Kubeconfig automatisch verwendet:

```bash
echo "${KUBECONFIG:-$HOME/.kube/config}"
oc whoami
oc get nodes
oc get co
```

Abmelden:

```bash
oc logout
```

## Lokale OpenShift-Namen auf dem SNO

Das Installations-Script erzeugt cluster-spezifische Einträge in `/etc/hosts`, z.B.:

```text
10.31.20.25 sno-terra5 sno-terra5.terra5.lernvirt.test
10.31.20.25 api.terra5.lernvirt.test
10.31.20.25 api-int.terra5.lernvirt.test
10.31.20.25 console-openshift-console.apps.terra5.lernvirt.test
10.31.20.25 oauth-openshift.apps.terra5.lernvirt.test
```

Die erkannten Clusterparameter stehen zusätzlich unter:

```text
/var/lib/lernvirt/cluster.env
```

Anzeigen:

```bash
sudo cat /var/lib/lernvirt/cluster.env
```

## Wichtige Pfade

Auf der SNO-Maschine:

```text
/etc/hostname
/etc/hosts
/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
/etc/profile.d/lernvirt-openshift.sh
/var/lib/lernvirt/cluster.env
```

Auf dem PXE-Server:

```text
/srv/tftp/config/openshift-sno.conf
/srv/tftp/grub/stacks/openshift-sno.cfg
/var/www/html/openshift-sno/
```

## Kurzcheck nach erfolgreicher Installation

```bash
sudo -i
export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig

hostnamectl
oc get nodes -o wide
oc get co
oc get clusterversion
oc whoami --show-console
```

Erwartet wird ein einzelner Node mit den Rollen:

```text
control-plane,master,worker
```
