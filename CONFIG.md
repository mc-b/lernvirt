## 4. Konfiguration

### 4.1 `values.yaml` anpassen

Die zentrale Konfiguration erfolgt über `values.yaml`.

Beispiel:

    # VMs welche erstellt werden sollen. 
    vm:
      count: 24
      
      # VM Default Werte - koennen ueberschrieben werden
      cpu: 1
      memory: 512Mi
      storage: 1Gi
      # userdata eine Liste von Fallback-URLs, die der Reihe nach probiert werden.
      # der letzte Eintrag verwendet https://github.com/mc-b/lernmaas Logik (= Hostname) zum bestimmen des Scripts
      userdata:
        - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/master/cloud-init.yaml
        - https://raw.githubusercontent.com/tbz-it/{{RELEASE}}/refs/heads/main/cloud-init.yaml
        - https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml
    
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
      
    # Cloud-init Datasource - fuer nfsclient.sh, mounted /data etc.  
    datasource:
      serverIP: 10.10.0.5

**Bedeutung der wichtigsten Parameter:**

* `vm.count` -   Anzahl der zu erstellenden virtuellen Maschinen
* `vm.userdata` - Fallback-URLs wo Cloud-Init-Konfiguration gesucht werden.
* `wgClients.endpointNode` - URL unter welche der Zugriff via WireGuard VPN erfolgt
* `mirror.enabled + mirrorBaseUrl` - Ist ein lokale Mirror für die VM Images vorhanden und wo (siehe [Installation](INSTALL.md)).
* `datasource.serverIP` - wird mit einer zentralen NFS Ablage gearbeitet ist hier die IP des NFS-Servers einzutragen

### 4.2 Beispiele

Das Verzeichnis examples/ enthält optionale, in sich geschlossene Beispiele, die typische Einsatz- und Lernszenarien mit KubeVirt und Kubernetes demonstrieren.

* [Alpine Linux](examples/alpine/README.md)
* [Docker, Podman und Kubernetes](examples/duk/README.md)
* [GNS3 Labor](examples/gns3/README.md)
* [Windows 10](examples/win10/README.md)
* [Windows Server 2022](examples/wins2022/README.md)
* [lernvirt nur als Wireguard Gateway Server verwenden](examples/gateway/README.md)
* [AI Umgebung](examples/aiaas/README.md)

