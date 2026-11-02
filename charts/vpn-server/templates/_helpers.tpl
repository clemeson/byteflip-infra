{{- define "vpn.name" -}}
{{- .Values.nameOverride | default .Release.Name -}}
{{- end -}}

{{- define "vpn.labels" -}}
app: {{ include "vpn.name" . }}
app.kubernetes.io/name: {{ include "vpn.name" . }}
app.kubernetes.io/part-of: {{ .Release.Namespace }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vpn.chapSecrets" -}}
{{- printf "%s/chap-secrets" .Values.persistence.mountPath -}}
{{- end -}}
