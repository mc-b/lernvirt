# sglang-model Helm Chart

Dieses Helm Chart deployt einen SGLang Model Server in Kubernetes mit:

- PersistentVolumeClaim für den HuggingFace-Cache
- Ablage der Dateien unter `/root/.cache/huggingface`
- Speicherung in einem Unterverzeichnis im PVC mit dem Namen:
  `<release-name>-<chart-name>`
- optional aktivierbarer `runtimeClassName`
- variablem Modellnamen
- variablem Container-Image

## Installation


Chart direkt aus dem Verzeichnis installieren:

    cd examples/aiaas/helm/sglang
    helm install qwen .

## Weitere Modelle starten

    helm install smollm2 .      --set model.name=HuggingFaceTB/SmolLM2-1.7B-Instruct
    helm install smollm2-135m . --set model.name=HuggingFaceTB/SmolLM2-135M-Instruct
    
    helm install qwen-coder .   --set model.name=Qwen/Qwen2.5-Coder-0.5B

    helm install tiny-llama .   --set model.name=TinyLlama/TinyLlama-1.1B-Chat-v1.0
    
    helm install apertus .      --set model.name=swiss-ai/Apertus-8B-Instruct-2509 --set model.memFraction=0.40
    
    helm install qwen7b .      --set model.name=Qwen/Qwen2.5-7B-Instruct --set model.memFraction=0.40

## Deinstallation

    helm uninstall qwen
    etc.

## Hinweise

* Das PVC wird vom Deployment unter `/root/.cache/huggingface` eingebunden.
* Durch `subPath: {{ .Release.Name }}-{{ .Chart.Name }}` werden die Daten in einem eigenen Unterverzeichnis abgelegt.
* Die GPU-Resource ist aktuell standardmässig in `values.yaml` gesetzt. Wenn du das Deployment vollständig ohne GPU betreiben willst, solltest du zusätzlich die Resource-Werte anpassen.

## Links

* [swiss-ai/Apertus-8B-Instruct-2509](https://huggingface.co/swiss-ai/Apertus-8B-Instruct-2509)
