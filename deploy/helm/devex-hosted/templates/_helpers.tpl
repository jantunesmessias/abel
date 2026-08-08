{{- define "devex-hosted.name" -}}devex-hosted{{- end }}
{{- define "devex-hosted.labels" -}}
app.kubernetes.io/name: {{ include "devex-hosted.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{- define "devex-hosted.remoteWebImage" -}}
{{- $image := required "remote.webWorkerImage is required" .Values.remote.webWorkerImage -}}
{{- if not (regexMatch "^.+@sha256:[0-9a-f]{64}$" $image) -}}
{{- fail "remote.webWorkerImage must be pinned by sha256 digest" -}}
{{- end -}}
{{- $image -}}
{{- end }}
{{- define "devex-hosted.remoteAndroidImage" -}}
{{- $image := required "remote.androidWorkerImage is required" .Values.remote.androidWorkerImage -}}
{{- if not (regexMatch "^.+@sha256:[0-9a-f]{64}$" $image) -}}
{{- fail "remote.androidWorkerImage must be pinned by sha256 digest" -}}
{{- end -}}
{{- $image -}}
{{- end }}
{{- define "devex-hosted.remoteRoleName" -}}
{{- printf "%s-%s-remote-runtime" .Release.Namespace (include "devex-hosted.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- define "devex-hosted.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devex-hosted.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- define "devex-hosted.image" -}}
{{- required "image.digest is required; mutable tags are forbidden" .Values.image.digest -}}
{{ printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- end }}
