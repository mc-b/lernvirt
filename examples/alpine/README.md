alpine
----

**Alpine Linux** ist eine schlanke, sichere und ressourcensparende Linux-Distribution, die besonders für Server, Container und virtuelle Umgebungen geeignet ist. 

In dieser Umgebung steht eine **kleine Alpine-Installation** zur Verfügung, in der bereits grundlegende Dienste wie **NFS** für Dateifreigaben und **WireGuard** 
für sichere Netzwerkverbindungen eingerichtet sind.

Weitere Software wird unter Alpine einfach über den Paketmanager **`apk`** installiert, z. B. mit `apk add <paketname>`. 

Installation

    helm install lab . -n alpine --create-namespace -f examples/alpine/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n alpine
    
Löschen

    helm uninstall lab -n alpine && kubectl delete ns alpine    
    
Testen

    virtctl console vm-0 -n alpine 
    
