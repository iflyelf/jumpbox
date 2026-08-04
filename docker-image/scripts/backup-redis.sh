#!/bin/bash
#=================================================
# Redis 备份脚本 (支持逻辑备份和物理备份)
# 作者: iflyelf
# 说明:
#   - 逻辑备份: redis-cli --rdb (远程拉取RDB快照)
#   - 物理备份: 直接复制宿主机 RDB/AOF 文件 (需挂载数据目录)
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

# Redis 连接信息
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# 物理备份数据目录 (宿主机挂载路径)
REDIS_DATADIR="${REDIS_DATADIR:-/data/redis/data}"

# 备份输出目录
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/data/backups/redis}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"

# 保留天数
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 集群标识
CLUSTER_NAME="${CLUSTER_NAME:-redis-cluster}"

# 构造 redis-cli 认证参数
REDIS_AUTH=()
if [ -n "${REDIS_PASSWORD}" ]; then
    REDIS_AUTH=(-a "${REDIS_PASSWORD}" --no-auth-warning)
fi

# ==================== 逻辑备份 (redis-cli --rdb) ====================
backup_logical() {
    log "开始 Redis 逻辑备份 (redis-cli --rdb)..."
    
    mkdir -p "${BACKUP_DIR}"
    
    # 检查连接
    if ! redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" "${REDIS_AUTH[@]}" PING &>/dev/null; then
        error "无法连接到 Redis: ${REDIS_HOST}:${REDIS_PORT}"
    fi
    
    log "连接成功: ${REDIS_HOST}:${REDIS_PORT}"
    
    local BACKUP_FILE="${BACKUP_DIR}/${CLUSTER_NAME}-${TIMESTAMP}.rdb"
    
    # --rdb: 远程拉取 RDB 快照到本地文件
    log "拉取 RDB 快照: ${BACKUP_FILE}"
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" "${REDIS_AUTH[@]}" \
        --rdb "${BACKUP_FILE}"
    
    # 压缩
    gzip "${BACKUP_FILE}"
    
    local BACKUP_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
    log "逻辑备份完成: ${BACKUP_FILE}.gz (大小: ${BACKUP_SIZE})"
}

# ==================== 物理备份 (复制RDB/AOF文件) ====================
backup_physical() {
    log "开始 Redis 物理备份 (复制数据文件)..."
    
    # 检查数据目录
    if [ ! -d "${REDIS_DATADIR}" ]; then
        error "Redis 数据目录不存在: ${REDIS_DATADIR} (需挂载宿主机数据目录)"
    fi
    
    mkdir -p "${BACKUP_DIR}"
    
    log "数据目录: ${REDIS_DATADIR}"
    
    # 先触发 BGSAVE 确保数据落盘
    if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" "${REDIS_AUTH[@]}" PING &>/dev/null; then
        log "触发 BGSAVE..."
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" "${REDIS_AUTH[@]}" BGSAVE || true
        # 等待 BGSAVE 完成
        sleep 5
    fi
    
    local BACKUP_FILE="${BACKUP_DIR}/${CLUSTER_NAME}-physical-${TIMESTAMP}.tar.gz"
    
    # 复制 RDB 和 AOF 文件
    log "打包数据文件: ${BACKUP_FILE}"
    tar -czf "${BACKUP_FILE}" -C "${REDIS_DATADIR}" \
        $(cd "${REDIS_DATADIR}" && ls *.rdb *.aof appendonlydir 2>/dev/null || echo ".") 2>/dev/null || \
        tar -czf "${BACKUP_FILE}" -C "${REDIS_DATADIR}" .
    
    local BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "物理备份完成: ${BACKUP_FILE} (大小: ${BACKUP_SIZE})"
}

# ==================== 清理旧备份 ====================
cleanup_old_backups() {
    log "清理 ${RETENTION_DAYS} 天前的旧备份..."
    
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true
    
    log "旧备份清理完成"
}

# ==================== 主流程 ====================
main() {
    log "========================================"
    log "Redis 备份开始"
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
    log "Redis 备份完成"
    log "备份位置: ${BACKUP_DIR}"
    log "========================================"
}

main "$@"
