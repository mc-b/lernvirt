# llama-server-intel Helm Chart

Dieses Chart deployt `llama.cpp` als `Deployment` plus `Service` auf Kubernetes. Das Binary wird ohne separates Dockerfile per `initContainer` als `.tar.gz` heruntergeladen, in ein gemeinsames `emptyDir` entpackt und danach im Hauptcontainer gestartet.

Die Chart-Voreinstellung basiert auf Intel GPU und Vulkan:

- Download des Releases `llama-b8457-bin-ubuntu-vulkan-x64.tar.gz`
- Start von `llama-server`
- Installation der nötigen Runtime-Pakete im Hauptcontainer
- einfacher Vulkan-Selbsttest mit `vulkaninfo`
- Nutzung einer Intel-GPU über Kubernetes-Resource, standardmässig `gpu.intel.com/i915: 1`

## Voraussetzungen

- Kubernetes-Cluster mit funktionierendem Intel GPU Device Plugin
- Der Pod muss im Container Zugriff auf `/dev/dri/*` erhalten
- Die Resource im Cluster muss zum Node passen, z. B.:
  - `gpu.intel.com/i915`
  - oder `gpu.intel.com/xe`

Wenn dein Node statt `i915` die Resource `xe` publiziert, passe `values.yaml` entsprechend an.

## Installation

    cd helm/llama

    helm install llama-qwen .

Oder mit eigenem Namespace:

    helm install llama-qwen . -n llama --create-namespace

## Konfiguration

### weitere Modelle

    helm install llama-smollm2 . --set server.hfModel="HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF:Q4_K_M"

    helm install llama-gemma .   --set server.hfModel="ggml-org/gemma-3-1b-it-GGUF"

Weitere Modelle [Hugging Face Hub](https://huggingface.co/ggml-org).

### GPU-Resource auf `xe` umstellen

Lege z. B. eine Datei `my-values.yaml` an:

    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
        gpu.intel.com/xe: "1"
      requests:
        cpu: "2"
        memory: "4Gi"

Dann:

    helm upgrade --install llama-server-intel ./llama-server-intel-helm-chart -f my-values.yaml

## Debugging

Im Kubernetes Cluster

    sudo intel_gpu_top

Logs des Hauptcontainers:

    kubectl logs deployment/llama-server-intel-llama-server-intel -c llama

Im Pod prüfen, ob die GPU-Geräte sichtbar sind:

    kubectl exec -it deploy/llama-server-intel-llama-server-intel -c llama -- bash -lc 'ls -l /dev/dri'

Vulkan im Container prüfen:

    kubectl exec -it deploy/llama-server-intel-llama-server-intel -c llama -- bash -lc 'vulkaninfo | head -50'

Verfügbare `llama.cpp`-Devices prüfen:

    kubectl exec -it deploy/llama-server-intel-llama-server-intel -c llama -- bash -lc '
    LLAMA_SERVER="$(find /work -type f -name llama-server | head -n 1)"
    "$LLAMA_SERVER" --list-devices

## Hinweise

1. Der Container installiert bei jedem Pod-Start Pakete per `apt-get`. Das ist absichtlich so gelöst, weil kein separates Dockerfile verwendet wird.
2. Wenn `vulkaninfo` im Container mit „Found no drivers“ scheitert, fehlen meist Userspace-Treiber oder ICD-Dateien. Deshalb wird `mesa-vulkan-drivers` installiert.
3. Standardmässig werden Ubuntu 24.04 und ein `NodePort`-Service verwendet.
4. [ggml-org](https://github.com/ggml-org/)
