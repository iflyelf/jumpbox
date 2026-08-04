#!/bin/bash
#=================================================
# 统一备份调度入口
# 作者: iflyelf
# 说明: 按需调度 MySQL / PostgreSQL / Redis 备份
#=================================================

set -uo pipefail

export TZ=Asia/Shanghai

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 备份开关 (由环境变量控制)
BACKUP_MYSQL_ENABLED="${BACKUP_MYSQL_ENABLED:-false}"
BACKUP_POSTGRES_ENABLED="${BACKUP_POSTGRES_ENABLED:-false}"
BACKUP_REDIS_ENABLED="${BACKUP_REDIS_ENABLED:-false}"

FAILED=0

log "========================================"
log "统一数据库备份任务开始"
log "MySQL: ${BACKUP_MYSQL_ENABLED} | PostgreSQL: ${BACKUP_POSTGRES_ENABLED} | Redis: ${BACKUP_REDIS_ENABLED}"
log "========================================"

if [ "${BACKUP_MYSQL_ENABLED}" = "true" ]; then
    log ">>> 执行 MySQL 备份"
    if ! bash "${SCRIPT_DIR}/backup-mysql.sh"; then
        log "MySQL 备份失败"
        FAILED=1
    fi
fi

if [ "${BACKUP_POSTGRES_ENABLED}" = "true" ]; then
    log ">>> 执行 PostgreSQL 备份"
    if ! bash "${SCRIPT_DIR}/backup-postgres.sh"; then
        log "PostgreSQL 备份失败"
        FAILED=1
    fi
fi

if [ "${BACKUP_REDIS_ENABLED}" = "true" ]; then
    log ">>> 执行 Redis 备份"
    if ! bash "${SCRIPT_DIR}/backup-redis.sh"; then
        log "Redis 备份失败"
        FAILED=1
    fi
fi

log "========================================"
if [ "${FAILED}" -eq 0 ]; then
    log "所有备份任务完成"
else
    log "部分备份任务失败, 请检查日志"
fi
log "========================================"

exit ${FAILED}
