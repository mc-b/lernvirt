alpine
----


Installation

    helm install lab . -n alpine --create-namespace -f examples/alpine/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n alpine
    
Löschen

    helm uninstall lab -n alpine && kubectl delete ns alpine    
    
Testen

    virtctl console vm-0 -n alpine 
    
