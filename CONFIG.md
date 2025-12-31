## 4. Konfiguration

### 4.1 `values.yaml` anpassen

Die zentrale Konfiguration erfolgt über `values.yaml`.

Beispiel:

    # VMs welche erstellt werden sollen. 
    vm:
      count: 3
      
      # VM Default Werte - koennen ueberschrieben werden
      cpu: 1
      memory: 512Mi
      storage: 1Gi
      userdata: https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/examples/alpine/cloud-init.yaml
    
    os:
      name: alpine         # ubuntu | alpine | windows
      variant: edge       # linux: noble, jammy | windows: win10, win11, ws2022

    # WireGuard Clients. WireGuard erreichbar via Host
    wgClients:
      startHostId: 100
      count: 30
      endpointNode: cloud.tbz.ch
      
    # Lokaler Image Cache vorhanden? (lokaler nginx Server von oben)
    mirror:
      enabled: true
      storage:
        size: 50Gi  
      mirrorBaseUrl: http://image-mirror

**Bedeutung der wichtigsten Parameter:**

* `vm.count` -   Anzahl der zu erstellenden virtuellen Maschinen
* `vm.userdata` - Cloud-Init-Konfiguration (Benutzer, SSH-Key, Pakete, Netzwerke)
* `vm.image.url` - Quelle des VM-Basisimages (lokaler Mirror empfohlen)
* `wgClients.count` - Anzahl automatisch generierter WireGuard-Client-Konfigurationen

### 4.2 Beispiele

Das Verzeichnis examples/ enthält optionale, in sich geschlossene Beispiele, die typische Einsatz- und Lernszenarien mit KubeVirt und Kubernetes demonstrieren.

* [Alpine Linux](examples/alpine/README.md)
* [Docker, Podman und Kubernetes](examples/duk/README.md)
* [GNS3 Labor](examples/gns3/README.md)
* [Windows 10](examples/win10/README.md)
* [Windows Server 2022](examples/wins2022/README.md)
