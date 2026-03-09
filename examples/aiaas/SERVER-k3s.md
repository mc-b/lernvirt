## AI Server mit k3s

**Damit AI Server und die Client Notebooks zusammen sauber funktionieren, sollten diese auf dem Client regelmässig aktualisiert werden, siehe [Jupyter Lab](https://github.com/mc-b/lernvirt/tree/main/examples/aiaas#jupyter-lab).**

Für die Funktionsfähigkeit der beschriebenen Konfigurationen kann keine Gewähr übernommen werden. Bei Abweichungen oder Problemen sollte die jeweils aktuelle offizielle Dokumentation konsultiert werden.

### Installation k3s

Am einfachsten das Installationsscript [k3scontrol.sh](https://raw.githubusercontent.com/mc-b/lerncloud/main/services/k3scontrol.sh) verwenden.

    sudo -i
    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/k3scontrol.sh | bash
    
Kontrolle

    kubectl get nodes -o wide
    
### Nvidia GPU Operator

Für DGX Spark kein DRA für GPU-Allocation, sondern GPU Operator + klassisches NVIDIA Device Plugin + Time-Slicing verwenden.

    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
    
    helm upgrade --install gpu-operator nvidia/gpu-operator \
      --version=v25.10.1 \
      --namespace gpu-operator \
      --create-namespace \
      --set driver.enabled=false \
      --set toolkit.enabled=false
   
ConfigMap mit den Anzahl `replicas` = virtuelle GPUs   
     
    kubectl apply -f - <<EOF      
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: time-slicing-config
      namespace: gpu-operator
    data:
      any: |-
        version: v1
        flags:
          migStrategy: none
        sharing:
          timeSlicing:
            resources:
            - name: nvidia.com/gpu
              replicas: 16     
    EOF

Aktualisieren des GPU Operators

    helm upgrade --install gpu-operator nvidia/gpu-operator \
      --version=v25.10.1 \
      --namespace gpu-operator \
      --create-namespace \
      --set driver.enabled=false \
      --set toolkit.enabled=false \
      --set devicePlugin.config.name=time-slicing-config \
      --set devicePlugin.config.default=any

Kontrolle

    kubectl get nodes -o json | jq '.items[].status.allocatable'
    kubectl describe node $(kubectl get nodes -o name | cut -d/ -f2) | grep -A5 -B2 nvidia.com/gpu    
    
Testen mit 8 Pods welche alle eine GPU brauchen

    kubectl apply -f - <<EOF
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: gpu-test
    spec:
      replicas: 8
      selector:
        matchLabels:
          app: gpu-test
      template:
        metadata:
          labels:
            app: gpu-test
        spec:
          containers:
          - name: cuda-test
            image: nvidia/cuda:12.4.1-base-ubuntu22.04
            command: ["bash","-c"]
            args:
              - |
                echo "Pod $(hostname) started";
                while true; do
                  nvidia-smi;
                  sleep 30;
                done
            resources:
              limits:
                nvidia.com/gpu: 1
    EOF
        
    for p in $(kubectl get pods -A -o name | grep gpu-test); do echo $p && kubectl logs $p | head -4 ; done    
    
    kubectl delete deployment gpu-test    
    
**Hinweis**: ab Kubernetes 1.35 wird diese Variante durch den [NVIDIA DRA Driver for GPUs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html) abgelöst.

**Links**

* [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/overview.html)
* [Container Device Interface (CDI) Support in the GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/cdi.html)
* [GPU Operator with KubeVirt](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-kubevirt.html)
* [Time-Slicing GPUs in Kubernetes (alt)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
* [NVIDIA DRA Driver for GPUs (neu)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html)
* [Dynamic Resource Allocation(neu)](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)

