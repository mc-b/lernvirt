Cloud-native Umgebung
---------------------

### Beinhaltet

* Juypter Lab inkl. AI Notebooks
* K3s - Control Plane Node und 2 Worker Nodes
* Docker
* Podman
* Cert Manager
* Istio
* K-native
* KubeVirt
* Longhorn
* ArgoCD
* IIoT Custom Resource Definitions und Operator

### Installation

Host spezifische Werte festlegen

    HELM_VALUES_HOST=hosts/<host>.yaml
    
Minimale Umgebung (k3s, JupyterLab, docker, podman, istio)
    
    helm install cna . -n cna --create-namespace -f ${HELM_VALUES_HOST} -f examples/cna/values.yaml 
    
Komplette Umgebung inkl. aller Produkte oben   
    
    helm install cna . -n cna --create-namespace -f ${HELM_VALUES_HOST} -f examples/cna/values-full.yaml     
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n cna
    
WireGuard aktivieren und dann sind die AI Notebooks und das CNA README wie folgt erreichbar:

* [AI Notebooks](http://10.10.1.10:32188/lab)
* [CNA README](http://10.10.1.10:32188/lab/tree/CnA/2_Unterrichtsressourcen/A-infra/README.ipynb )    
    
Löschen

    helm uninstall cna -n cna && kubectl delete ns cna    
    
Testen

    virtctl console vm-0 -n cna   
    
    ssh -i ~/.ssh/lerncloud ubuntu@10.10.1.10  
    
### Troubleshooting

siehe [duk](../duk/README.md)
      