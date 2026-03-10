# sglang-model Helm Chart

Dieses Helm Chart deployt einen SGLang Model Server in Kubernetes mit:

- PersistentVolumeClaim für den HuggingFace-Cache
- Ablage der Dateien unter `/root/.cache/huggingface`
- Speicherung in einem Unterverzeichnis im PVC mit dem Namen:
  `<release-name>-<chart-name>`
- optional aktivierbarer `runtimeClassName`
- variablem Modellnamen
- variablem Container-Image

## Verzeichnisstruktur

```text
sglang-model/
├── Chart.yaml
├── values.yaml
├── README.md
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── pvc.yaml
    └── service.yaml
````

## Installation

Chart direkt aus dem Verzeichnis installieren:

```bash
helm install qwen ./sglang-model
```

Dabei entsteht für den Cache das Unterverzeichnis:

```text
qwen-sglang-model
```

## Konfiguration

### Anderes Modell setzen

```bash
helm install qwen ./sglang-model \
  --set model.name=Qwen/Qwen2.5-7B-Instruct
```

### Anderes Container-Image setzen

```bash
helm install qwen ./sglang-model \
  --set image.repository=docker.io/lmsysorg/sglang \
  --set image.tag=v0.5.9-cu130-runtime
```

### NVIDIA RuntimeClass deaktivieren

```bash
helm install qwen ./sglang-model \
  --set runtimeClass.enabled=false
```

### Andere RuntimeClass setzen

```bash
helm install qwen ./sglang-model \
  --set runtimeClass.enabled=true \
  --set runtimeClass.name=nvidia
```

### PVC-Grösse ändern

```bash
helm install qwen ./sglang-model \
  --set pvc.size=100Gi
```

### StorageClass setzen

```bash
helm install qwen ./sglang-model \
  --set pvc.storageClassName=longhorn
```

## Upgrade

```bash
helm upgrade qwen ./sglang-model
```

## Deinstallation

```bash
helm uninstall qwen
```

## Hinweise

* Das PVC wird vom Deployment unter `/root/.cache/huggingface` eingebunden.
* Durch `subPath: {{ .Release.Name }}-{{ .Chart.Name }}` werden die Daten in einem eigenen Unterverzeichnis abgelegt.
* Die GPU-Resource ist aktuell standardmässig in `values.yaml` gesetzt. Wenn du das Deployment vollständig ohne GPU betreiben willst, solltest du zusätzlich die Resource-Werte anpassen.

**Hinweis**:
Noch ein wichtiger Hinweis: Das Chart oben funktioniert grundsätzlich, aber `subPath` legt das Unterverzeichnis nicht automatisch an, wenn es im Volume noch nicht existiert. Je nach Storage-Treiber kann der Pod dann beim Start fehlschlagen. Die robustere Variante ist ein `initContainer`, der das Verzeichnis zuerst erstellt. 
