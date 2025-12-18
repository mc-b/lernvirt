Docker, PodMan und Kubernetes Umgebung
--------------------------------------

### Beinhaltet

* Docker
* Podman
* K3s - Control Plane Node und 2 Worker Nodes
* Istio
* Juypter Notebooks

**Hinweis** microk8s läuft innerhalb von kubevirt nicht, weil calico das Netzwerk zu stark verändert.
    
### Installation

    helm install lab . -n duk --create-namespace -f examples/values-duk.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n duk
    
Löschen

    helm uninstall lab -n duk && kubectl delete ns duk    
    
Testen

    virtctl console vm-0 -n duk   
    
    ssh -i ~/.ssh/lerncloud ubuntu@10.10.0.10  