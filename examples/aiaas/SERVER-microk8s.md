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

Überprüfen ob die Datei `/var/snap/microk8s/current/args/containerd-template.toml` bereits nvidia Einträge hat.

    sudo grep nvidia /var/snap/microk8s/current/args/containerd-template.toml
 
**Wenn Nein**: Konfiguriere die Container-Laufzeitumgebung mit folgendem nvidia-ctk Befehl:

    sudo nvidia-ctk runtime configure --runtime=containerd --config /var/snap/microk8s/current/args/containerd-template.toml 
    
**Nvidia Operator** installieren 

    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
    
    helm upgrade --install gpu-operator nvidia/gpu-operator \
      --version=v25.10.1 \
      --namespace gpu-operator \
      --create-namespace \
      --set driver.enabled=false \
      --set toolkit.enabled=false    
    
Wenn das fehlschlägt, bzw. die Init-Container nicht starten, bearbeite diese Datei (genau diese, nicht /etc/containerd/...):

    sudo vi /var/snap/microk8s/current/args/containerd-template.toml

Entferne `-container-runtime` hinter `nvidia` in den Zeilen mit `[plugins....]`

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime]
      runtime_type = "${RUNTIME_TYPE}"
    
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime.options]
        BinaryName = "nvidia-container-runtime"

Starte `containerd` und `microk8s` neu

    sudo systemctl daemon-reload
    sudo systemctl restart containerd
    sudo snap restart microk8s    
    
**ACHTUNG**: bei allen Container welche die GPU nützen wollen muss `runtimeClassName: nvidia` gesetzt sein:

    spec:
      runtimeClassName: nvidia
    
Weiter geht es bei [k3s Nvidia GPU Operator](Server-k3s.md).

**Links**

* [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/overview.html)
* [microk8s Installation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#microk8s)
* [Container Device Interface (CDI) Support in the GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/cdi.html)
* [GPU Operator with KubeVirt](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-kubevirt.html)
* [Time-Slicing GPUs in Kubernetes (alt)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
* [NVIDIA DRA Driver for GPUs (neu)](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html)
* [Dynamic Resource Allocation(neu)](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)

