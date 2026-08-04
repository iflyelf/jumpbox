{{/*
展开 chart 名称
*/}}
{{- define "jumpbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
完整名称
*/}}
{{- define "jumpbox.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart 标识
*/}}
{{- define "jumpbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
公共标签
*/}}
{{- define "jumpbox.labels" -}}
helm.sh/chart: {{ include "jumpbox.chart" . }}
{{ include "jumpbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
application/jumpbox: "true"
{{- end }}

{{/*
选择器标签
*/}}
{{- define "jumpbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jumpbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount 名称
*/}}
{{- define "jumpbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "jumpbox.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
数据库凭证 Secret 名称 (Chart 自动生成的明文 Secret)
*/}}
{{- define "jumpbox.secretName" -}}
{{- printf "%s-db-credentials" (include "jumpbox.fullname" .) }}
{{- end }}

{{/*
凭证校验: 数据库启用时必须提供 existingSecret 或 password, 否则报错。
生产环境推荐使用 existingSecret 以避免在 values 中出现明文密码。
*/}}
{{- define "jumpbox.validateCredentials" -}}
{{- $mysql := .Values.databases.mysql -}}
{{- $pg := .Values.databases.postgres -}}
{{- $redis := .Values.databases.redis -}}
{{- if and $mysql.enabled (not $mysql.existingSecret) (not $mysql.auth.password) }}
{{- fail "databases.mysql 已启用, 但未提供凭证。请设置 databases.mysql.existingSecret (生产推荐) 或 databases.mysql.auth.password" }}
{{- end }}
{{- if and $pg.enabled (not $pg.existingSecret) (not $pg.auth.password) }}
{{- fail "databases.postgres 已启用, 但未提供凭证。请设置 databases.postgres.existingSecret (生产推荐) 或 databases.postgres.auth.password" }}
{{- end }}
{{- if and $redis.enabled (not $redis.existingSecret) (not $redis.auth.password) }}
{{- fail "databases.redis 已启用, 但未提供凭证。请设置 databases.redis.existingSecret (生产推荐) 或 databases.redis.auth.password" }}
{{- end }}
{{- end }}

{{/*
是否需要 Chart 生成明文 Secret (任一启用的库使用了 auth.password 而非 existingSecret)
*/}}
{{- define "jumpbox.createInternalSecret" -}}
{{- $mysql := .Values.databases.mysql -}}
{{- $pg := .Values.databases.postgres -}}
{{- $redis := .Values.databases.redis -}}
{{- if or (and $mysql.enabled (not $mysql.existingSecret) $mysql.auth.password) (and $pg.enabled (not $pg.existingSecret) $pg.auth.password) (and $redis.enabled (not $redis.existingSecret) $redis.auth.password) -}}
true
{{- end -}}
{{- end }}

{{/*
脚本 ConfigMap 名称
*/}}
{{- define "jumpbox.scriptsConfigMapName" -}}
{{- printf "%s-scripts" (include "jumpbox.fullname" .) }}
{{- end }}

{{/*
数据库连接环境变量 (供 StatefulSet 和 CronJob 共用)
*/}}
{{- define "jumpbox.dbEnvVars" -}}
{{- $mysql := .Values.databases.mysql -}}
{{- $pg := .Values.databases.postgres -}}
{{- $redis := .Values.databases.redis -}}
{{- if $mysql.enabled }}
- name: MYSQL_HOST
  value: {{ $mysql.host | quote }}
- name: MYSQL_PORT
  value: {{ $mysql.port | quote }}
- name: MYSQL_USER
  value: {{ $mysql.auth.username | quote }}
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      {{- if $mysql.existingSecret }}
      name: {{ $mysql.existingSecret }}
      key: {{ $mysql.existingSecretPasswordKey }}
      {{- else }}
      name: {{ include "jumpbox.secretName" . }}
      key: mysql-password
      {{- end }}
- name: MYSQL_DATADIR
  value: {{ $mysql.datadir | quote }}
{{- end }}
{{- if $pg.enabled }}
- name: PG_HOST
  value: {{ $pg.host | quote }}
- name: PG_PORT
  value: {{ $pg.port | quote }}
- name: PG_USER
  value: {{ $pg.auth.username | quote }}
- name: PG_DATABASE
  value: {{ $pg.auth.database | quote }}
- name: PG_PASSWORD
  valueFrom:
    secretKeyRef:
      {{- if $pg.existingSecret }}
      name: {{ $pg.existingSecret }}
      key: {{ $pg.existingSecretPasswordKey }}
      {{- else }}
      name: {{ include "jumpbox.secretName" . }}
      key: postgres-password
      {{- end }}
- name: PG_DATADIR
  value: {{ $pg.datadir | quote }}
- name: PGBACKREST_STANZA
  value: {{ $pg.pgbackrestStanza | quote }}
{{- end }}
{{- if $redis.enabled }}
- name: REDIS_HOST
  value: {{ $redis.host | quote }}
- name: REDIS_PORT
  value: {{ $redis.port | quote }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      {{- if $redis.existingSecret }}
      name: {{ $redis.existingSecret }}
      key: {{ $redis.existingSecretPasswordKey }}
      {{- else }}
      name: {{ include "jumpbox.secretName" . }}
      key: redis-password
      {{- end }}
- name: REDIS_DATADIR
  value: {{ $redis.datadir | quote }}
{{- end }}
- name: BACKUP_BASE_DIR
  value: {{ .Values.backup.targetPath | quote }}
- name: RETENTION_DAYS
  value: {{ .Values.backup.retentionDays | quote }}
- name: BACKUP_MODE
  value: {{ .Values.backup.mode | quote }}
- name: BACKUP_MYSQL_ENABLED
  value: {{ $mysql.enabled | quote }}
- name: BACKUP_POSTGRES_ENABLED
  value: {{ $pg.enabled | quote }}
- name: BACKUP_REDIS_ENABLED
  value: {{ $redis.enabled | quote }}
- name: TZ
  value: {{ .Values.backup.timeZone | default "Asia/Shanghai" | quote }}
{{- end }}

{{/*
宿主机卷定义 (volumes)
*/}}
{{- define "jumpbox.hostVolumes" -}}
{{- range .Values.extraHostVolumeMounts }}
- name: {{ .name }}
  hostPath:
    path: {{ .hostPath }}
    type: {{ .type | default "DirectoryOrCreate" }}
{{- end }}
{{- end }}

{{/*
宿主机卷挂载 (volumeMounts)
*/}}
{{- define "jumpbox.hostVolumeMounts" -}}
{{- range .Values.extraHostVolumeMounts }}
- name: {{ .name }}
  mountPath: {{ .mountPath }}
  readOnly: {{ .readOnly | default false }}
{{- end }}
{{- end }}
