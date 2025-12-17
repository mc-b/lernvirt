{{- define "vm.values" -}}
{{- $i := .index | int -}}
{{- $vals := .values -}}
{{- $base := deepCopy $vals.vm -}}
{{- $override := index $vals (printf "vm-%d" $i) | default dict -}}
{{- mergeOverwrite $base $override | toYaml -}}
{{- end -}}
