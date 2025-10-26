{{- define "web-ui.name" -}}
{{- include "common.name" . -}}
{{- end -}}

{{- define "web-ui.fullname" -}}
{{- include "common.fullname" . -}}
{{- end -}}

{{- define "web-ui.labels" -}}
{{ include "common.labels" . }}
{{- end -}}

{{- define "web-ui.selectorLabels" -}}
{{ include "common.selectorLabels" . }}
{{- end -}}

{{- define "web-ui.serviceAccountName" -}}
{{- include "common.serviceAccountName" . -}}
{{- end -}}
