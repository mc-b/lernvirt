# Host-spezifische `<host>.yaml`

Host-spezifische `<hosts>.yaml`-Dateien beschreiben **Eigenschaften und Rahmenbedingungen eines konkreten Hosts oder Kubernetes-Clusters**.

Sie definieren **lokale Infrastruktur-Details**, die sich von Host zu Host unterscheiden können, aber **unabhängig von Umgebung (dev/prod) oder CI-Logik** sind.

Diese Dateien werden typischerweise beim **Context-Switch** (z. B. `cts gx10`) automatisch geladen und ergänzen die globalen Standard-Values des Helm-Charts.

Diese Dateien werden als letztes an Helm übergeben, z.B. Deployment auf ARM64 Plattform

    helm install alpine . -f examples/alpine/values.yaml -f hosts/gx10.yaml
    
oder Deployment auf X86_64 Plattform

    helm install alpine . -f examples/alpine/values.yaml -f hosts/kvc.yaml    

## Zweck

Host-Values beantworten Fragen wie:

* Wie viele Ressourcen stehen auf diesem Host zur Verfügung?
* Wie sind die Services erreichbar (z. B. WireGuard, Image-Mirror)?
* Welche CPU-Architektur wird verwendet?

Sie beschreiben damit **was der Host kann**, nicht **wie oder wann etwas deployed wird**.

## Typische Inhalte

    vm:
      count: 3
    
    # WireGuard Clients. WireGuard erreichbar via Host
    wgClients:
      count: 3
      endpointNode: 192.168.1.56
      
    # Lokaler Image Cache vorhanden? 
    mirror:
      enabled: true
      mirrorBaseUrl: http://192.168.1.56
      
    # Cloud-init Datasource - fuer nfsclient.sh, mounted /data etc.  
    datasource:
      serverIP: 192.168.1.56   
        
    # Bestimmung OS, Version und CPU Architektur  
    os:
      architecture: arm64  # amd64 | arm64    

