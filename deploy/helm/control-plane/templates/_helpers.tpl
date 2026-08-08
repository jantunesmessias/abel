{{- define "control-plane.name" -}}control-plane{{- end }}
{{- define "control-plane.labels" -}}
app.kubernetes.io/name: {{ include "control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{- define "control-plane.remoteWebImage" -}}
{{- $image := required "remote.webWorkerImage is required" .Values.remote.webWorkerImage -}}
{{- if not (regexMatch "^.+@sha256:[0-9a-f]{64}$" $image) -}}
{{- fail "remote.webWorkerImage must be pinned by sha256 digest" -}}
{{- end -}}
{{- $image -}}
{{- end }}
{{- define "control-plane.remoteAndroidImage" -}}
{{- $image := required "remote.androidWorkerImage is required" .Values.remote.androidWorkerImage -}}
{{- if not (regexMatch "^.+@sha256:[0-9a-f]{64}$" $image) -}}
{{- fail "remote.androidWorkerImage must be pinned by sha256 digest" -}}
{{- end -}}
{{- $image -}}
{{- end }}
{{- define "control-plane.remoteRoleName" -}}
{{- printf "%s-%s-remote-runtime" .Release.Namespace (include "control-plane.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- define "control-plane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- define "control-plane.image" -}}
{{- required "image.digest is required; mutable tags are forbidden" .Values.image.digest -}}
{{ printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- end }}
