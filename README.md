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

## 2. + 3. Voraussetzungen und Installation

* [Installation](INSTALL.md)

---

## 4. Konfiguration

* [Konfiguration](CONFIG.md)

---

## 5. Deployment der VMs

### 5.1 Erstellen einer Modulumgebung für eine Klasse

    helm install m122 oci://ghcr.io/mc-b/lernvirt -n ap21a --create-namespace
    
Es werden alle Module von [lernmaas](https://github.com/mc-b/lernmaas), siehe `config.yaml` unterstützt. Weil `microk8s` 
innerhalb von `kubevirt` nicht funktioniert, gibt es für bestimmte Module, z.B. m169, eine m169k3s Variante.
    
Für nicht auf [lernmaas](https://github.com/mc-b/lernmaas) basierende Module siehe [Konfiguration und Beispiele](CONFIG.md).

Für Hosts spezifische Anpassungen wie Image Mirror, ARM64 etc. siehe [hosts](hosts/README.md)

### 5.2 Status & Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n ap21a

Typische Ressourcen:

* `DataVolume` - (VM-Image)
* `PersistentVolumeClaim` - (Storage)
* `VirtualMachine` / `VirtualMachineInstance`

### 5.3 Zugriff auf VM-Konsole

    virtctl console m122-lernvirt-vm-0 -n ap21a

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