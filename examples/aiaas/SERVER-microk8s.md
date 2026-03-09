### Konfiguration

Die Installation geht davon aus, dass wir uns auf einer Maschine mit GB10, z.B. Asus Ascent GX10, befinden.

Ausserdem ist `microk8s` z.B. in der [lernvirt Variante](https://github.com/mc-b/lernvirt) installiert.

Prüfen ob Treiber installiert sind

    nvidia-smi
    
Und ob microk8s diese verwendet

    microk8s kubectl describe node | grep -A5 -E "nvidia.com|gpu"    
    
Installation der Packages

    sudo apt-get install nvidia-container-toolkit -y
    
**containerd konfigurieren (für Kubernetes)**
 
Konfigurieren Sie die Container-Laufzeitumgebung mit folgendem nvidia-ctkBefehl:

    sudo nvidia-ctk runtime configure --runtime=containerd
    
Standardmässig nvidia-ctk erstellt der Befehl eine `/etc/containerd/conf.d/99-nvidia.toml` Konfigurationsdatei und ändert (oder erstellt) `/etc/containerd/config.toml` diese, um sicherzustellen, dass die importsKonfigurationsoption entsprechend aktualisiert wird. Die Konfigurationsdatei gewährleistet, dass containerd die NVIDIA Container Runtime nutzen kann.

containerd neu starten:

    sudo systemctl restart containerd    
    
Starten des K8s Device Plugins

    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
      
    helm install gpu-operator -n gpu-operator --create-namespace \
      nvidia/gpu-operator $HELM_OPTIONS \
        --version=v25.10.1 \
        --set toolkit.env[0].name=CONTAINERD_CONFIG \
        --set toolkit.env[0].value=/var/snap/microk8s/current/args/containerd-template.toml \
        --set toolkit.env[1].name=CONTAINERD_SOCKET \
        --set toolkit.env[1].value=/var/snap/microk8s/common/run/containerd.sock \
        --set toolkit.env[2].name=RUNTIME_CONFIG_SOURCE \
        --set-string toolkit.env[2].value=file=/var/snap/microk8s/current/args/containerd.toml    
    
Runtime in containerd auf nvidia umbenennen

Bearbeite diese Datei (genau diese, nicht /etc/containerd/...):

    sudo vi /var/snap/microk8s/current/args/containerd-template.toml

Entferne `-container-runtime` hinter `nvidia` in der plugins Zeile

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime]
      runtime_type = "${RUNTIME_TYPE}"
    
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime.options]
        BinaryName = "nvidia-container-runtime"

Starte `microk8s` neu

Prüfen ob GPU vorhanden ist:

    kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{" allocatable="}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
    
Weiter bei [K3s Nvidia GPU Operator](Server-k3s.md).

**Links**

* [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/overview.html)
* [microk8s Installation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#microk8s)
* [Container Device Interface (CDI) Support in the GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/cdi.html)
* [GPU Operator with KubeVirt](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-kubevirt.html)
* [Time-Slicing GPUs in Kubernetes (alt)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
* [NVIDIA DRA Driver for GPUs (neu)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html)
* [Dynamic Resource Allocation(neu)](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)

