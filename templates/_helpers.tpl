{{- define "vm.values" -}}
{{- $i := .index | int -}}
{{- $vals := .values -}}
{{- $base := deepCopy $vals.vm -}}
{{- $override := index $vals (printf "vm-%d" $i) | default dict -}}
{{- mergeOverwrite $base $override | toYaml -}}
{{- end -}}

{{/*
Release name
*/}}
{{- define "lernvirt.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "lernvirt.fullname" -}}
{{ printf "%s-%s" .Release.Name (include "lernvirt.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "lernvirt.labels" -}}
app.kubernetes.io/name: {{ include "lernvirt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

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

{{/*
Generate deterministic locally administered unicast MAC address.
*/}}
{{- define "lernvirt.macAddress" -}}
{{- $root := .root -}}
{{- $index := .index -}}
{{- $mac := default dict (index $root.Values "mac") -}}
{{- $seed := default "" (index $mac "seed") -}}
{{- $input := printf "%s/%s/%s/%d" $seed $root.Release.Namespace $root.Release.Name $index -}}
{{- $hash := sha256sum $input -}}
{{- printf "02:%s:%s:%s:%s:%s" (substr 0 2 $hash) (substr 2 4 $hash) (substr 4 6 $hash) (substr 6 8 $hash) (substr 8 10 $hash) -}}
{{- end -}}

