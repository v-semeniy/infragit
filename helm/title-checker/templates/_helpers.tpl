{{/*
Повна назва ресурсу
*/}}
{{- define "title-checker.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Назва chart-у
*/}}
{{- define "title-checker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Стандартні labels для всіх ресурсів
*/}}
{{- define "title-checker.labels" -}}
helm.sh/chart: {{ include "title-checker.chart" . }}
{{ include "title-checker.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (для matchLabels)
*/}}
{{- define "title-checker.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service Account name
*/}}
{{- define "title-checker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "title-checker.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
