Cloud-native Umgebung
---------------------

### Beinhaltet

* Docker
* Podman
* K3s - Control Plane Node und 2 Worker Nodes
* Cert Manager
* Istio
* K-native
* Longhorn
* ArgoCD
* AutoShop inkl. IIoT
* Juypter Notebooks

### Installation

    HELM_VALUES_HOST=hosts/<host>.yaml
    
    helm install cna . -n cna --create-namespace -f ${HELM_VALUES_HOST} -f examples/cna/values.yaml 
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n cna
    
Löschen

    helm uninstall cna -n cna && kubectl delete ns cna    
    
Testen

    virtctl console vm-0 -n cna   
    
    ssh -i ~/.ssh/lerncloud ubuntu@10.10.1.10  
    
### Troubleshooting

siehe [duk](../duk/README.md)
      