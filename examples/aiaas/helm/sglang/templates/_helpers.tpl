{{- define "sglang-model.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "sglang-model.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name -}}
{{- end -}}