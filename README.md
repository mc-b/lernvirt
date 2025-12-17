# Lernumgebung mit KubeVirt auf microk8s Kubernetes

lernvirt ist eine Lernumgebung auf Basis von KubeVirt, betrieben auf microk8s Kubernetes, mit der sich virtuelle Maschinen und Kubernetes-Konzepte praxisnah, lokal und reproduzierbar erlernen lassen.
Der Fokus liegt auf einfacher Infrastruktur, klaren Helm-Charts und transparenter Storage-Nutzung für Schulungs- und Experimentierzwecke.


## 0. Quick Start

**Kubernetes Installation**

Auf Bare Metall eine [zentrale Dateiablage](https://raw.githubusercontent.com/mc-b/lerncloud/main/services/nfsshare.sh) und [microk8s](https://raw.githubusercontent.com/mc-b/lerncloud/main/services/microk8s.sh) aufsetzen, z.B. mittels als root

    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/nfsshare.sh | bash -
    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/microk8s.sh | bash -
    
KubeVirt aktivieren (als user ubuntu)

    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/kubevirt.sh | bash -
    
Emulation ggf. wieder deaktivieren

    kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":false}}}}'     
    
Falls die Images gecacht werden sollen, diese nach `/data/images` downloaden, z.B. 

    mkdir -p /data/images
    cd /data/images
    wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
    
[values.yaml](values.yaml) anpassen.
    
    vm:
      count: 3
      # VM Default Werte - koennen ueberschrieben werden
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
        
Wieviele VMs `vm.count`, welches Cloud-init Script `vm.userdata`, wieviele Client WireGuard Konfigurationen erstellen

**VMs in Kubernetes erstellen**

Installation

    helm install lab . -n m346-ap21a --create-namespace

    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n m346-ap21a
    
Löschen

    helm uninstall lab -n m346-ap21a && kubectl delete ns m346-ap21a    
    
Testen

    virtctl console vm-0 -n m346-ap21a 

**Client Zugriff**

Müssen WireGuard aktiviert haben. Anzeige der WireGuard Konfiguration siehe von `helm`, z.B.:

    kubectl get secret client-100 \
      -n m346-ap21a \
      -o jsonpath='{.data.wg0\.conf}' | base64 -d
 
ssh-Zugriff 

    ssh -i ~/.ssh/lerncloud debian@10.10.0.10    
   
---

## 1. Zielsetzung

Bereitstellung einer **isolierten, skalierbaren Lernumgebung** pro Modul/Klasse, in der:

* jede VM automatisch einen **eigenen WireGuard-Key** erhält
* externe Clients (LE, Admins) **sicher von ausserhalb** zugreifen können
* **keine manuellen Konfigurationsschritte** im Cluster nötig sind

---

## 2. Gesamtübersicht (logisch)

```
┌───────────────────────────┐
│        Externer Client     │
│  (LE / Admin / Laptop)     │
│                             │
│  WireGuard Client           │
│  PrivateKey (lokal)         │
└─────────────┬─────────────┘
              │ UDP/31820
              ▼
┌──────────────────────────────────────────┐
│ Kubernetes Node                           │
│                                          │
│  NodePort Service (wg-gateway)            │
│  UDP 31820 → 51820                        │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ WireGuard Gateway Pod               │  │
│  │                                    │  │
│  │  wg0 Interface                     │  │
│  │  PrivateKey (lokal im Pod)          │  │
│  │                                    │  │
│  │  controller.sh                     │  │
│  │  - liest Secrets                   │  │
│  │  - synchronisiert WG-Peers         │  │
│  └───────────────┬────────────────────┘  │
│                  │                         │
│                  │ kubectl get secrets     │
│                  ▼                         │
│        Kubernetes Secrets (Namespace)      │
│        ──────────────────────────────      │
│        vm-0                     │
│        vm-1                     │
│        client-100                          │
│        client-101                          │
│        └─ publickey                        │
│        └─ userData (cloud-init)            │
└──────────────────┬────────────────────────┘
                   │
                   │ virtio / cloud-init
                   ▼
┌──────────────────────────────────────────┐
│ KubeVirt VM (Studenten-VM)                │
│                                          │
│  cloud-init                               │
│  - erzeugt /etc/wireguard/wg0.conf        │
│  - enthält PrivateKey (nur in VM)         │
│                                          │
│  WireGuard wg0                            │
│  IP: 10.10.0.x                            │
└──────────────────────────────────────────┘
```

---

## 3. Zentrale Komponenten

### 3.1 WireGuard Gateway

* läuft als **privilegierter Pod**
* hält **keine Client-PrivateKeys**
* kennt **nur PublicKeys**
* synchronisiert Peers **dynamisch**

**Aufgaben:**

* Terminierung aller VPN-Verbindungen
* Routing zwischen externen Clients und VMs
* Automatisches Hinzufügen/Entfernen von Peers

---

### 3.2 Keygen Job

* läuft **einmalig pro Helm-Deployment**
* erzeugt pro VM:

  * PrivateKey (nur für VM)
  * PublicKey (für Gateway)
* erstellt Kubernetes Secrets:

  * `vm-<n>`

**Wichtig:**

* PrivateKeys verlassen **nie** die VM
* PublicKeys sind **die einzige Quelle** für Peer-Management

---

### 3.3 Kubernetes Secrets = Desired State

Jedes Secret repräsentiert **einen WireGuard-Peer**.

Beispiel:

```
Secret: vm-0
  ├─ publickey   → Gateway liest diesen
  └─ userData    → VM nutzt diesen
```

**Regel:**

> Existiert ein Secret → Peer ist erlaubt
> Wird ein Secret gelöscht → Peer wird entfernt

---

### 3.4 Controller (`controller.sh`)

* läuft dauerhaft im Gateway-Pod
* arbeitet **polling-basiert**
* kein Custom Controller, kein CRD

**Algorithmus (vereinfacht):**

```
loop alle 15s:
  secrets = kubectl get secrets
  desired_keys = secrets.publickey
  current_keys = wg show peers

  add peers, die fehlen
  remove peers, die nicht mehr existieren
```

---

## 4. Netzwerkdesign

| Netz           | Zweck             |
| -------------- | ----------------- |
| `10.10.0.0/24` | WireGuard Overlay |
| `10.10.0.1`    | Gateway           |
| `10.10.0.10+`  | VMs               |
| `10.10.0.250`  | Externe Clients   |

---

## 5. Sicherheitsprinzipien

* **PrivateKeys bleiben immer beim Besitzer**

* VM-Keys nur in der VM
* Gateway sieht **ausschliesslich PublicKeys**
* Zugriff wird **durch Secret-Existenz** gesteuert

---

## 6. Typischer Ablauf (End-to-End)

1. Helm installiert Namespace + Ressourcen
2. Keygen Job erzeugt Secrets
3. VMs booten und konfigurieren WG per cloud-init
4. Gateway-Controller liest Secrets
5. Peers werden automatisch konfiguriert
6. Externer Client verbindet sich per NodePort
7. Zugriff auf VMs ist möglich

---

## 7. Didaktische Einordnung (SEUSAG)

* klare Trennung von:

  * **Infrastruktur**
  * **Automatisierung**
  * **Security**
  
* gut geeignet für:

  * M346 / M347 / M183
  * Netzwerke, VPN, Cloud-Grundlagen
* Architektur ist:

  * transparent
  * reproduzierbar
  * realitätsnah

---
   