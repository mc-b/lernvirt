Windows Server 2022
----

Die Windows Images wurden mit Packer erstellt.

Funktionieren mit KVM, QEmu, Proxmoxx etc.

Siehe
* https://github.com/mc-b/terra/tree/main/01-5-packer-windows

Installation

    helm install lab . -n wins2022 --create-namespace -f examples/wins2022/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n wins2022
    
Löschen

    helm uninstall lab -n wins2022 && kubectl delete ns wins2022    
    
Testen

    virtctl vnc vm-0 -n wins2022 

**Einschränkungen**

Braucht entsprechende virt Treiber ansonsten startet Windows nicht.