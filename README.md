# Lernumgebung mit KubeVirt auf microk8s

<img src="https://kubevirt.io/user-guide/assets/architecture-simple.png"
     alt="KubeVirt Architektur"
     style="max-width: 60%;">


Quelle: [KubeVirt Architektur – User Guide](https://kubevirt.io/user-guide/architecture/)

- - -

**lernvirt** ist eine lokale, reproduzierbare Lernumgebung auf Basis von Kubernetes und KubeVirt.
Sie ermöglicht es, **virtuelle Maschinen als Kubernetes-Ressourcen** zu betreiben und dabei sowohl klassische Virtualisierung als auch Kubernetes-Konzepte praxisnah zu erlernen.

## 1. Zielpublikum

Die Umgebung eignet sich besonders für:

* Unterrichtsmodule und Schulungen
* Klassen- oder Kursumgebungen
* lokale Test- und Entwicklungsumgebungen

**Beispiele**:

**Module aus [Modulbaukasten (MBK)](https://www.modulbaukasten.ch/)**

Host spezifische Werte festlegen (wird beim Erstellen der lernvirt Umgebung erstellt)

    HELM_VALUES_HOST=hosts/<host>.yaml

Modul M122 - Automatisieren mit Skripten. Cloud-init Deklaration von [https://github.com/tbz-it/M122](https://github.com/tbz-it/M122) wird verwendet

    helm install m122-ap21a-ben . -n ap21a --create-namespace -f ${HELM_VALUES_HOST} 
    
Modul M169 Services mit Containern bereitstellen. Cloud-init Script von [lernmaas]() wird verwendet.

    helm install m169k3s-ap21a-ben . -n ap21a --create-namespace -f ${HELM_VALUES_HOST} 
  
Aufbau Helm Instanz Namen: [Modul]-[Klasse]-[Lehrerkürzel]
    
**Weitere**

* [Alpine Linux](examples/alpine/README.md)
* [Modul CNA (K3s, Docker, PodMan, KubeVirt, Longhorn, Cert-Manager, Harbor, Istio, K-native, IIoT)](examples/cna/README.md)
* [Docker, Podman und Kubernetes](examples/duk/README.md)
* [GNS3 Labor](examples/gns3/README.md)
* [Windows 10](examples/win10/README.md)
* [Windows Server 2022](examples/wins2022/README.md)
* [lernvirt nur als Wireguard Gateway Server verwenden](examples/gateway/README.md)
* [AI Umgebung](examples/aiaas/README.md)
* [Dev Container](examples/devcontainer/README.md)
* [WSL Umgebungen](examples/wsl/README.md)

---

## 2. + 3. Voraussetzungen und Installation

* [Installation](INSTALL.md)
* Für bestehende lernMAAS Umgebungen siehe [Migration](MIGRATION.md)

---

## 4. Konfiguration

* [Konfiguration](CONFIG.md)

---

## 5. Deployment der VMs

Eine Anleitung für Cloud Umgebungen, wie z.B. AWS, Azure, MAAS.io siehe [cloud](cloud/README.md). Dazu wird [opentofu](https://opentofu.org/) (fork von [terraform](https://developer.hashicorp.com/terraform)) verwendet.

### 5.1 Erstellen einer Modulumgebung für eine Klasse

    helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace
    
 Dieses Chart stellt die KubeVirt-Umgebung bereit und liest das passende cloud-init-Script über `vm.userdata` ein (siehe [CONFIG.md](CONFIG.md)). Dabei kann `vm.userdata` entweder eine einzelne URL oder eine Liste von Fallback-URLs sein; es wird jeweils die erste erreichbare (HTTP 200) verwendet.
 
Per Default werden folgende Fallback-URLs verwendet:

    vm:
      userdata:
        - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/master/cloud-init.yaml
        - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/main/cloud-init.yaml
        - https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml 
 
d.h. für m122, siehe zuerst nach `https://raw.githubusercontent.com/tbz-it/m122/refs/heads/master/cloud-init.yaml`, dann im `main`-Branch und verwende dann die [lernmaas](https://github.com/mc-b/lernmaas) Logik über dessen [config.yaml](https://github.com/mc-b/lernmaas/blob/master/config.yaml).

Die VMs verwenden 2 Cores und 2 GB an Memory. Dieses kann mittels `--set vm.memory` oder `vm.cpu` überschrieben werden:

    helm install m169k3s oci://ghcr.io/mc-b/lernmaas -n ap21a --create-namespace --set vm.memory=4Gi
    
Für Hosts spezifische Anpassungen wie Image Mirror, ARM64 etc. siehe [hosts](hosts/README.md)

**Hinweis**: Weil `microk8s` innerhalb von `kubevirt` nicht funktioniert, gibt es für bestimmte Module, z.B. m169, eine m169k3s Variante.

### 5.2 Status & Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n ap21a

Typische Ressourcen:

* `DataVolume` - (VM-Image)
* `PersistentVolumeClaim` - (Storage)
* `VirtualMachine` / `VirtualMachineInstance`

Wenn das Dashboard aktiviert ist, kann über https://<Control Plane>:30443 darauf zugegriffen werden. Die relevanten Informationen werden dabei grafisch dargestellt.

Für den Zugriff ist ein Token erforderlich. Dieser kann wie folgt erstellt werden:

        kubectl -n kubernetes-dashboard create token dashboard-readonly --duration=8h

Wird die Option `--duration` nicht angegeben, ist der Token standardmässig eine Stunde gültig.

Das Dashboard kann auch manuell gestart werden:

    kubectl apply -f https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/addons/dashboard-readonly.yaml 
    kubectl apply -f https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/addons/dashboard-rbac.yaml  

### 5.3 Zugriff auf VM-Konsole

    virtctl console m122-lernmaas-vm-0 -n ap21a

### 5.4 Umgebung löschen

    helm uninstall m122 -n ap21a && kubectl delete ns ap21a

---

## 6. Client-Zugriff via WireGuard

Für jeden Client wird automatisch eine WireGuard-Konfiguration erzeugt.

Anzeige wie darauf zugegriffen werden kann:

    helm get notes m122 -n ap21a

Die Konfiguration kann direkt in einen WireGuard-Client importiert werden (Linux, macOS, Windows, Mobile).

---

## 7. SSH-Zugriff auf VMs

Nach erfolgreicher VPN-Verbindung ist der Zugriff per SSH möglich:

    ssh -i ~/.ssh/lerncloud debian@10.10.1.10

---

## 8. Client-Zugriff via Remotedesktop (RDP) für Windows

Neben dem Zugriff per SSH können **Windows-VMs** auch direkt über **Remote Desktop Protocol (RDP)** genutzt werden.

Dabei wird der **RDP-Port 3389** der jeweiligen VM über einen Kubernetes-Service nach aussen exponiert.

⚠️ **Hinweis:**
Ein direkt exponierter RDP-Port stellt ein erhöhtes Sicherheitsrisiko dar.
Für produktive oder internet-exponierte Umgebungen wird dringend empfohlen, den Zugriff **über das WireGuard-VPN** durchzuführen oder den NodePort per Firewall einzuschränken.

### 8.1 Service überprüfen

Mit folgendem Befehl kann überprüft werden, ob der RDP-Service aktiv ist:

    kubectl get service -n ap21a

Beispielausgabe:

    NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)           AGE
    vm-0           NodePort   10.152.183.12  <none>        3389:31234/TCP     2m

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

## 9. - 11. Erweiterungen

* [Autoinstall, PXE Boot, eigenes Netzwerk](CONFIG.md)

## 12. FAQ

* [Fragen und Antworten](FAQ.md)


- - -

<a rel="license" href="http://creativecommons.org/licenses/by/4.0/"><img alt="Creative Commons Lizenzvertrag" style="border-width:0" src="https://i.creativecommons.org/l/by/4.0/88x31.png" /></a><br />Dieses Werk ist lizenziert unter einer <a rel="license" href="http://creativecommons.org/licenses/by/4.0/">Creative Commons Namensnennung 4.0 International Lizenz</a>.

Copyright (C) mc-b.ch, Marcel Bernet

*Verlinkte Scripte können andere Copyrights beinhalten!*