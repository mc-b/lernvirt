## 2. Voraussetzungen

* Bare-Metal Host mit:

  * Linux (z.B. Ubuntu Server)
  * aktivierter Hardware-Virtualisierung (Intel VT-x / AMD-V)
* Root-Zugriff für die Initialinstallation
* Internetzugang (optional: lokaler Image-Cache)

## 3. Installation

Bei einer neu Installation auf Bare Metal [autoinstall](autoinstall/README.md) verwenden und weiter bei Punkt 3.5.

**Alternative**:

### 3.1 Kubernetes & Infrastruktur installieren

Auf dem Bare-Metal-Host werden zuerst eine zentrale Dateiablage (NFS) und microk8s installiert.

Als **root** ausführen:

    curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/scripts/install-lernvirt.sh | bash -
    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/microk8s.sh | bash -

### 3.2 KubeVirt aktivieren

Als **normaler Benutzer** (z.B. `ubuntu`):

    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/kubevirt.sh | bash -

Falls zuvor CPU-Emulation aktiviert wurde, kann diese wieder deaktiviert werden:

    kubectl -n kubevirt patch kubevirt kubevirt \
      --type=merge \
      --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":false}}}}'
      
Metrics Server um die Auslastung anzeigen zu können `kubectl top nodes`

    microk8s enable metrics-server
    
Rollenbasierter Access um unerlaubte Zugriffe zu unterbinden, aktiveren:
    
    microk8s enable rbac      

### 3.3 VM-Images vorbereiten (optional, empfohlen)

Dazu brauchen wir zuerst nginx

    sudo apt-get install nginx -y

dann Images nach `/var/www/html` herunterladen

    mkdir -p /var/www/html/linux
    cd /var/www/html/linux

Ubuntu 24.04 (noble)

    mkdir -p ubuntu/noble/{amd64,arm64}
    wget -P ubuntu/noble/amd64 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
    wget -P ubuntu/noble/arm64 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img

Alpine Linux (edge)

    mkdir -p alpine/edge/{amd64,arm64}
    wget -P alpine/edge/amd64 https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.0-x86_64-bios-cloudinit-r0.qcow2
    wget -P alpine/edge/arm64 https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.2-aarch64-uefi-cloudinit-r0.qcow2

Alle Images liegen danach unter:

    /var/www/html/linux/…
    
Eintrag in `values.yaml` eintragen, bzw. ändern

    # Lokaler Image Cache vorhanden? 
    mirror:
      enabled: true
      mirrorBaseUrl: http://<ip-adresse nginx>   

### 3.4 Storage einrichten

    sudo mkdir -p /data /data/storage /data/config /data/templates /data/config/ssh 
    sudo chown -R ubuntu:ubuntu /data
    sudo chmod 777 /data/storage   
    
    cat <<%EOF% | sudo tee /etc/exports
    # /etc/exports: the access control list for filesystems which may be exported
    #               to NFS clients.  See exports(5).
    # Storage RW
    #/data *(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
    /data/storage *(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
    # Templates RO
    /data/templates *(ro,sync,no_subtree_check)
    # Config RO
    /data/config *(ro,sync,no_subtree_check)
    # microk8s Hostpath
    /var/snap/microk8s/common/default-storage *(rw,sync,no_subtree_check,no_root_squash)
    %EOF%

    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server 
    
Eintrag in `values.yaml` eintragen, bzw. ändern

    datasource:
      serverIP: <IP mein NFS Server>   
    
### 3.5  MicroK8s-Standard-StorageClass

Bei ein paar Umgebungen (z.B. Single Node oder ARM64 Architektur) binden **PVs nicht mehr**, weil die MicroK8s-Standard-StorageClass `WaitForFirstConsumer` verwendet.
Bei **KubeVirt / DataVolumes** führt das zu einem Deadlock: PVC wartet auf VM → VM wartet auf PVC.

Sollte dieser Fall eintreten ist eine eigene StorageClass mit **sofortigem Binding** zu erstellen:

    kubectl apply -f - <<EOF
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: hostpath-immediate
    provisioner: microk8s.io/hostpath
    volumeBindingMode: Immediate
    reclaimPolicy: Delete
    EOF
    
Eintrag in `values.yaml` eintragen, bzw. ändern

    # StorageClass fuer DataVolume fuer Single Node, ARM64  
    storage:
      enabled: true
      className: "hostpath-immediate"  
    
### 3.6 Control Plane + Worker joinen

    ssh -i ~/.ssh/lerncloud ubuntu@kv-control
    microk8s add-node --token-ttl 3600 | grep worker | tail -1
    exit
    
    ssh -i ~/.ssh/lerncloud ubuntu@kv-worker-01
    # Ausgabe von microk8s add-node    
    
💡 **Tipp**: Richte mehrere Control Plane Nodes ein (High Availability Setup), damit der Cluster auch bei Ausfall eines Nodes weiterhin über die verbleibenden Control Plane Nodes erreichbar bleibt.

### 3.7 Kubernetes Port-Mapping eingrenzen

Standardmässig erlaubt MicroK8s (wie Kubernetes allgemein) NodePorts im Bereich `30000–32767`. Um das aus Sicherheits- oder Administrationsgründen einzugrenzen (z. B. auf `31000–31500`), musst du eine Einstellung am API-Server anpassen.

**API-Server-Konfiguration bearbeiten**

Öffne die Datei mit den Kubernetes API-Server-Argumenten:

    sudo vi /var/snap/microk8s/current/args/kube-apiserver

**Argument ergänzen oder anpassen**

Füge folgende Zeile hinzu **(oder passe sie an, wenn sie schon existiert)**:

    --service-node-port-range=31000-31500

**MicroK8s neu starten**

Damit die Änderungen wirksam werden, muss MicroK8s neu gestartet werden:

    sudo microk8s stop
    sudo microk8s start

### 3.8 Load Balancer aktivieren

MetalLB ist eine Load-Balancer-Implementierung für Bare-Metal -Kubernetes- Cluster, die Standard-Routingprotokolle verwendet.

MetalLB kann wie folgt in microk8s aktiviert werden:

    microk8s enable "metallb:10.0.24.XXX-10.0.24.XXX"
    
XXX ist durch den eigenen IP-Range zu ersetzen.

**Tipp**: siehe auch [LoadBalancer mit IPv6 Range](advanced/metallb-IPv6.md) 

    