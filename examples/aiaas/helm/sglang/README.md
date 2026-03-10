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

## Konfiguration

### Anderes Modell setzen

    helm install smollm2 . --set model.name=HuggingFaceTB/SmolLM2-135M-Instruct


## Deinstallation

    helm uninstall qwen

## Hinweise

* Das PVC wird vom Deployment unter `/root/.cache/huggingface` eingebunden.
* Durch `subPath: {{ .Release.Name }}-{{ .Chart.Name }}` werden die Daten in einem eigenen Unterverzeichnis abgelegt.
* Die GPU-Resource ist aktuell standardmässig in `values.yaml` gesetzt. Wenn du das Deployment vollständig ohne GPU betreiben willst, solltest du zusätzlich die Resource-Werte anpassen.
