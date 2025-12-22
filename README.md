# Lernumgebung mit KubeVirt auf microk8s

<img src="https://kubevirt.io/user-guide/assets/architecture-simple.png"
     alt="KubeVirt Architektur"
     style="max-width: 60%;">


Quelle: [KubeVirt Architektur – User Guide](https://kubevirt.io/user-guide/architecture/)

- - -

**lernvirt** ist eine lokale, reproduzierbare Lernumgebung auf Basis von Kubernetes und KubeVirt.
Sie ermöglicht es, **virtuelle Maschinen als Kubernetes-Ressourcen** zu betreiben und dabei sowohl klassische Virtualisierung als auch Kubernetes-Konzepte praxisnah zu erlernen.

Die Umgebung eignet sich besonders für:

* Unterrichtsmodule und Schulungen
* Klassen- oder Kursumgebungen
* lokale Test- und Entwicklungsumgebungen

---

## 1. Zielsetzung

Ziel ist die Bereitstellung einer **isolierten, skalierbaren Lernumgebung pro Modul oder Klasse**, in der:

* jede VM automatisch konfiguriert wird (Cloud-Init)
* jede VM einen **eigenen WireGuard-Schlüssel** erhält
* externe Clients (z.B. Lehrpersonen, Admins) **sicher von ausserhalb** zugreifen können
* **keine manuellen Konfigurationsschritte** im Kubernetes-Cluster erforderlich sind
* VMs vollständig über **Helm und Kubernetes-Ressourcen** verwaltet werden

---

## 2. Voraussetzungen

* Bare-Metal Host mit:

  * Linux (z.B. Ubuntu Server)
  * aktivierter Hardware-Virtualisierung (Intel VT-x / AMD-V)
* Root-Zugriff für die Initialinstallation
* Internetzugang (optional: lokaler Image-Cache)

---

## 3. Quick Start

Bei einer neu Installation auf Bare Metal [autoinstall](autoinstall/README.md) verwenden und weiter bei Punkt 3.4.

**Alternative**:

### 3.1 Kubernetes & Infrastruktur installieren

Auf dem Bare-Metal-Host werden zuerst eine zentrale Dateiablage (NFS) und microk8s installiert.

Als **root** ausführen:

    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/nfsshare.sh | bash -
    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/microk8s.sh | bash -
   

### 3.2 KubeVirt aktivieren

Als **normaler Benutzer** (z.B. `ubuntu`):

    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/kubevirt.sh | bash -

Falls zuvor CPU-Emulation aktiviert wurde, kann diese wieder deaktiviert werden:

    kubectl -n kubevirt patch kubevirt kubevirt \
      --type=merge \
      --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":false}}}}'

### 3.3 VM-Images vorbereiten (optional, empfohlen)

Um wiederholte Downloads zu vermeiden, können Cloud-Images lokal gecacht werden:

    mkdir -p /data/images
    cd /data/images
    wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
    
### 3.4 Control Plane + Worker joinen

    ssh -i ~/.ssh/lerncloud ubuntu@kv-control
    microk8s add-node | grep worker | tail -1
    exit
    
    ssh -i ~/.ssh/lerncloud ubuntu@kv-worker-01
    # Ausgabe von microk8s add-noe    
    
`/data` von Control Plane mounten

    sudo mount -t nfs kv-control:/data /data    

---

## 4. Konfiguration

### 4.1 `values.yaml` anpassen

Die zentrale Konfiguration erfolgt über `values.yaml`.

Beispiel:

    vm:
      count: 3
      # Standardwerte für alle VMs (können überschrieben werden)
      cpu: 2
      memory: 2Gi
      storage: 8Gi
      userdata: https://raw.githubusercontent.com/tbz-it/M100/refs/heads/master/cloud-init.yaml
      image:
        name: base-image
        url: http://image-mirror/noble-server-cloudimg-amd64.img
    
    wgClients:
      startHostId: 100
      count: 5
      endpointNode: 10.1.40.35


**Bedeutung der wichtigsten Parameter:**

* `vm.count` -   Anzahl der zu erstellenden virtuellen Maschinen
* `vm.userdata` - Cloud-Init-Konfiguration (Benutzer, SSH-Key, Pakete, Netzwerke)
* `vm.image.url` - Quelle des VM-Basisimages (lokaler Mirror empfohlen)
* `wgClients.count` - Anzahl automatisch generierter WireGuard-Client-Konfigurationen
* `endpointNode` -  Öffentliche IP oder DNS des WireGuard Gateways

---

## 5. Deployment der VMs

### 5.1 Installation

    git clone https://github.com/mc-b/lernvirt.git
    cd lernvirt
    helm install lab . -n m346-ap21a --create-namespace


### 5.2 Status & Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n m346-ap21a

Typische Ressourcen:

* `DataVolume` - (VM-Image)
* `PersistentVolumeClaim` - (Storage)
* `VirtualMachine` / `VirtualMachineInstance`

### 5.3 Zugriff auf VM-Konsole

    virtctl console vm-0 -n m346-ap21a

### 5.4 Umgebung löschen

    helm uninstall lab -n m346-ap21a && kubectl delete ns m346-ap21a

---

## 6. Client-Zugriff via WireGuard

Für jeden Client wird automatisch eine WireGuard-Konfiguration erzeugt.

Anzeige einer Client-Konfiguration:

    kubectl get secret client-100 \
      -n m346-ap21a \
      -o jsonpath='{.data.wg0\.conf}' | base64 -d

Die Konfiguration kann direkt in einen WireGuard-Client importiert werden (Linux, macOS, Windows, Mobile).

---

## 7. SSH-Zugriff auf VMs

Nach erfolgreicher VPN-Verbindung ist der Zugriff per SSH möglich:

    ssh -i ~/.ssh/lerncloud debian@10.10.0.10

---

## 8. Client-Zugriff via Remotedesktop (RDP) für Windows

Neben dem Zugriff per SSH können **Windows-VMs** auch direkt über **Remote Desktop Protocol (RDP)** genutzt werden.

Dabei wird der **RDP-Port 3389** der jeweiligen VM über einen Kubernetes-Service nach aussen exponiert.

⚠️ **Hinweis:**
Ein direkt exponierter RDP-Port stellt ein erhöhtes Sicherheitsrisiko dar.
Für produktive oder internet-exponierte Umgebungen wird dringend empfohlen, den Zugriff **über das WireGuard-VPN** durchzuführen oder den NodePort per Firewall einzuschränken.

### 8.1 Service überprüfen

Mit folgendem Befehl kann überprüft werden, ob der RDP-Service aktiv ist:

    kubectl get service -n m346-ap21a

Beispielausgabe:

    NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)           AGE
    vm-0-rdp       NodePort   10.152.183.12  <none>        3389:31234/TCP     2m

In diesem Beispiel:

* **Port 3389** ist der interne RDP-Port der VM
* **Port 31234** ist der von Kubernetes vergebene NodePort
* die VM ist über die IP-Adresse des Kubernetes-Nodes erreichbar

### 8.3 RDP-Verbindung herstellen

Auf einem Windows-Client:

1. **Remotedesktop-Verbindung** öffnen: (`mstsc.exe`)

2. Als Ziel angeben: `<Node-IP>:<NodePort>`

3. Mit dem in der VM konfigurierten Benutzer und Password anmelden: z. B. `vagrant/vagrant`

---

## 9. Examples

Das Verzeichnis examples/ enthält optionale, in sich geschlossene Beispiele, die typische Einsatz- und Lernszenarien mit KubeVirt und Kubernetes demonstrieren.

Die Beispiele sind:

* [Alpine Linux](examples/alpine/README.md)
* [Docker, Podman und Kubernetes](examples/duk/README.md)
* [GNS3 Labor](examples/gns3/README.md)
* [Windows 10](examples/win10/README.md)
* [Windows Server 2022](examples/wins2022/README.md)

---


## 10. Eigenes VM Netzwerk (multus)

* [CNI Multus](multus/README.md)




