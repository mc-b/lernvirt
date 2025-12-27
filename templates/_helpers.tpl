{{- define "vm.values" -}}
{{- $i := .index | int -}}
{{- $vals := .values -}}
{{- $base := deepCopy $vals.vm -}}
{{- $override := index $vals (printf "vm-%d" $i) | default dict -}}
{{- mergeOverwrite $base $override | toYaml -}}
{{- end -}}


{{/*
Merge global OS config with optional per-VM override
*/}}
{{- define "lernvirt.osForVM" -}}
{{- $global := .Values.os -}}
{{- $local := .os | default dict -}}
{{- merge $global $local | toYaml | fromYaml -}}   {{/* ← WICHTIG */}}
{{- end -}}


{{/*
Resolve final image URL (original or mirror)
*/}}
{{- define "lernvirt.imageForVM" -}}

{{- $os := .Values.os -}}
{{- $images := .Values.images -}}

{{- if not (hasKey $images $os.family) -}}
{{- fail (printf "images: unknown family '%s'" $os.family) -}}
{{- end -}}

{{- if not (hasKey (index $images $os.family) $os.name) -}}
{{- fail (printf "images: unknown name '%s'" $os.name) -}}
{{- end -}}

{{- if not (hasKey (index $images $os.family $os.name) $os.variant) -}}
{{- fail (printf "images: unknown variant '%s'" $os.variant) -}}
{{- end -}}

{{- if not (hasKey (index $images $os.family $os.name $os.variant) $os.architecture) -}}
{{- fail (printf "images: no image for arch '%s'" $os.architecture) -}}
{{- end -}}

{{- $img := index $images $os.family $os.name $os.variant $os.architecture -}}

{{- if .Values.mirror.enabled -}}
  {{- if not .Values.mirror.mirrorBaseUrl -}}
    {{- fail "mirror.enabled=true but mirror.mirrorBaseUrl is not set" -}}
  {{- end -}}

  {{- $filename := base $img -}}
  {{- printf "%s/%s/%s/%s/%s/%s"
        .Values.mirror.mirrorBaseUrl
        $os.family
        $os.name
        $os.variant
        $os.architecture
        $filename
  -}}
{{- else -}}
  {{- $img -}}
{{- end -}}

{{- end -}}
