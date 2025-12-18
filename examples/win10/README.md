win10
----

Die Windows Images wurden mit Packer erstellt.

Funktionieren mit KVM, QEmu, Proxmoxx etc.

Siehe
* https://github.com/mc-b/terra/tree/main/01-5-packer-windows

Installation

    helm install lab . -n win10 --create-namespace -f examples/win10/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n win10
    
Löschen

    helm uninstall lab -n win10 && kubectl delete ns win10    
    
Testen

    virtctl vnc vm-0 -n win10 
    
**Einschränkungen**

Braucht entsprechende virt Treiber ansonsten startet Windows nicht.