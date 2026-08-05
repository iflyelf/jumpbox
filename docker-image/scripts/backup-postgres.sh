#!/bin/bash
#=================================================
# PostgreSQL 备份脚本 (支持逻辑备份和物理备份)
# 作者: iflyelf
# 说明:
#   - 逻辑备份: pg_dumpall / pg_dump (远程网络备份)
#   - 物理备份: pgbackrest (需配置 stanza + 挂载数据目录)
#=================================================

set -euo pipefail

# 时区设置
export TZ=Asia/Shanghai

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

# ==================== 配置参数 ====================
# 备份模式: logical(逻辑), physical(物理), both(两者)
BACKUP_MODE="${BACKUP_MODE:-logical}"

# PostgreSQL 连接信息
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_PASSWORD="${PG_PASSWORD:-}"
PG_DATABASE="${PG_DATABASE:-postgres}"

# 物理备份配置 (pgbackrest)
PGBACKREST_STANZA="${PGBACKREST_STANZA:-db}"
PG_DATADIR="${PG_DATADIR:-/data/postgres/data}"

# 备份输出目录
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/data/backups/postgres}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"

# 保留天数
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 集群标识
CLUSTER_NAME="${CLUSTER_NAME:-pg-cluster}"

# 导出密码供 psql/pg_dump 使用
export PGPASSWORD="${PG_PASSWORD}"

# ==================== 逻辑备份 (pg_dumpall) ====================
backup_logical() {
    log "开始 PostgreSQL 逻辑备份 (pg_dump)..."
    
    mkdir -p "${BACKUP_DIR}"
    
    # 检查连接
    if ! psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" -c "SELECT 1;" &>/dev/null; then
        error "无法连接到 PostgreSQL: ${PG_HOST}:${PG_PORT}"
    fi
    
    log "连接成功: ${PG_HOST}:${PG_PORT}"
    
    # 1. 全局对象备份 (角色、表空间等)
    local GLOBALS_FILE="${BACKUP_DIR}/${CLUSTER_NAME}-globals-${TIMESTAMP}.sql.gz"
    log "备份全局对象: ${GLOBALS_FILE}"
    pg_dumpall -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" \
        --globals-only 2>/dev/null | gzip > "${GLOBALS_FILE}"
    
    # 2. 逐库备份 (custom 格式, 支持并行恢复)
    local DATABASES
    DATABASES=$(psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" \
        -tAc "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")
    
    for db in ${DATABASES}; do
        local DB_FILE="${BACKUP_DIR}/${CLUSTER_NAME}-${db}-${TIMESTAMP}.dump"
        log "备份数据库: ${db} -> ${DB_FILE}"
        # -Fc: custom 格式(压缩), -Z9: 最高压缩
        pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${db}" \
            -Fc -Z9 -f "${DB_FILE}" 2>/dev/null
    done
    
    local BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
    log "逻辑备份完成: ${BACKUP_DIR} (总大小: ${BACKUP_SIZE})"
}

# ==================== 物理备份 (pgbackrest) ====================
backup_physical() {
    log "开始 PostgreSQL 物理备份 (pgbackrest)..."
    
    # 检查 pgbackrest 是否可用
    if ! command -v pgbackrest >/dev/null 2>&1; then
        log "错误: pgbackrest 未安装。物理备份需要 pgbackrest 工具。"
        log "建议: 使用 BACKUP_MODE=logical (pg_dump 逻辑备份)。"
        return 1
    fi
    
    # 检查 pgbackrest 配置
    if [ ! -f /etc/pgbackrest/pgbackrest.conf ] && [ ! -f /etc/pgbackrest.conf ]; then
        log "警告: 未找到 pgbackrest 配置, 尝试使用环境变量配置..."
        # 生成临时配置
        mkdir -p /etc/pgbackrest
        cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-path=${BACKUP_BASE_DIR}/pgbackrest
repo1-retention-full=2
log-level-console=info

[${PGBACKREST_STANZA}]
pg1-path=${PG_DATADIR}
pg1-host=${PG_HOST}
pg1-port=${PG_PORT}
pg1-user=${PG_USER}
EOF
    fi
    
    mkdir -p "${BACKUP_BASE_DIR}/pgbackrest"
    
    # 检查 stanza, 不存在则创建
    if ! pgbackrest --stanza="${PGBACKREST_STANZA}" info &>/dev/null; then
        log "创建 pgbackrest stanza: ${PGBACKREST_STANZA}"
        pgbackrest --stanza="${PGBACKREST_STANZA}" stanza-create || \
            error "pgbackrest stanza 创建失败, 请检查配置和数据目录 ${PG_DATADIR}"
    fi
    
    # 执行全量备份
    log "执行 pgbackrest 全量备份..."
    pgbackrest --stanza="${PGBACKREST_STANZA}" --type=full backup
    
    log "物理备份完成, 仓库位置: ${BACKUP_BASE_DIR}/pgbackrest"
    pgbackrest --stanza="${PGBACKREST_STANZA}" info
}

# ==================== 清理旧备份 ====================
cleanup_old_backups() {
    log "清理 ${RETENTION_DAYS} 天前的旧备份..."
    
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type d -regex '.*/[0-9]+_[0-9]+' -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true
    
    log "旧备份清理完成 (pgbackrest 仓库按 repo1-retention-full 自动管理)"
}

# ==================== 主流程 ====================
main() {
    log "========================================"
    log "PostgreSQL 备份开始"
    log "集群: ${CLUSTER_NAME}"
    log "模式: ${BACKUP_MODE}"
    log "========================================"
    
    case "${BACKUP_MODE}" in
        logical)
            backup_logical
            ;;
        physical)
            backup_physical
            ;;
        both)
            backup_logical
            backup_physical
            ;;
        *)
            error "未知备份模式: ${BACKUP_MODE} (支持: logical, physical, both)"
            ;;
    esac
    
    cleanup_old_backups
    
    log "========================================"
    log "PostgreSQL 备份完成"
    log "========================================"
}

main "$@"
