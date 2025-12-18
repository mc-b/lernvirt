GNS3
----

GNS3 (Graphical Network Simulator 3) ist eine leistungsfähige Open-Source-Plattform zur Simulation komplexer Netzwerke mit virtuellen Routern, Switches und Endgeräten. Sie wird häufig in Ausbildung, Laborumgebungen und zur Vorbereitung auf Zertifizierungen eingesetzt. GNS3 ermöglicht es, reale Netzwerkszenarien praxisnah zu entwerfen, zu testen und zu analysieren, ohne physische Hardware zu benötigen.


Installation

    helm install lab . -n gns3 --create-namespace -f examples/gns3/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n gns3
    
Löschen

    helm uninstall lab -n gns3 && kubectl delete ns gns3    
    
Testen

    virtctl console vm-0 -n gns3 
    
**Einschränkungen**

microk8s läuft innerhalb von kubevirt nicht, weil calico das Netzwerk zu stark verändert.