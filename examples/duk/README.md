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

    helm install lab . -n duk --create-namespace -f examples/duk/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n duk
    
Löschen

    helm uninstall lab -n duk && kubectl delete ns duk    
    
Testen

    virtctl console vm-0 -n duk   
    
    ssh -i ~/.ssh/lerncloud ubuntu@10.10.0.10  
    
### Troubleshooting

**SSH**

Die Control Plane Node (vm-0) kann `ssh vm-1` ausführen aber nicht umgekehrt.

Lösung: statt vm-0, WireGuard IP-Adresse 10.10.0.10 verwenden. Bsp:

    ssh vm-1 -- "sudo mount -t nfs 10.10.0.10:/data /data; df -h | grep /data" 
    
**nginx**

Verteilen sich die Pods auf drei Nodes bekommt der nginx ein Problem, weil alle Nodes die gleiche IP 10.0.2.2 haben.

Im Single Node Umfeld arbeiten.
      