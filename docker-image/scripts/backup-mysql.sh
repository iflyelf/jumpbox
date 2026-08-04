#!/bin/bash
#=================================================
# MySQL 备份脚本 (支持逻辑备份和物理备份)
# 作者: iflyelf
# 说明: 
#   - 逻辑备份: mysqldump (远程网络备份)
#   - 物理备份: xtrabackup (需同节点+挂载数据目录)
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

# MySQL 连接信息 (从环境变量或 Secret 读取)
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/run/mysqld/mysqld.sock}"

# 物理备份数据目录 (宿主机挂载路径)
MYSQL_DATADIR="${MYSQL_DATADIR:-/data/mysql/data}"

# 备份输出目录
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/data/backups/mysql}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"

# 保留天数
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 集群标识 (用于多集群场景)
CLUSTER_NAME="${CLUSTER_NAME:-mysql-cluster}"

# ==================== 逻辑备份 (mysqldump) ====================
backup_logical() {
    log "开始 MySQL 逻辑备份 (mysqldump)..."
    
    mkdir -p "${BACKUP_DIR}"
    
    local BACKUP_FILE="${BACKUP_DIR}/${CLUSTER_NAME}-logical-${TIMESTAMP}.sql.gz"
    
    # 检查连接
    if ! mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" &>/dev/null; then
        error "无法连接到 MySQL: ${MYSQL_HOST}:${MYSQL_PORT}"
    fi
    
    log "连接成功: ${MYSQL_HOST}:${MYSQL_PORT}"
    log "备份文件: ${BACKUP_FILE}"
    
    # mysqldump 参数说明:
    # --single-transaction: 一致性快照(InnoDB)
    # --routines: 包含存储过程和函数
    # --triggers: 包含触发器
    # --events: 包含事件调度器
    # --master-data=2: 记录binlog位置(注释形式)
    # --all-databases: 所有数据库
    mysqldump -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --master-data=2 \
        --all-databases \
        --default-character-set=utf8mb4 \
        2>/dev/null | gzip > "${BACKUP_FILE}"
    
    local BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "逻辑备份完成: ${BACKUP_FILE} (大小: ${BACKUP_SIZE})"
}

# ==================== 物理备份 (xtrabackup) ====================
backup_physical() {
    log "开始 MySQL 物理备份 (xtrabackup)..."
    
    # 检查数据目录是否存在
    if [ ! -d "${MYSQL_DATADIR}" ]; then
        error "MySQL 数据目录不存在: ${MYSQL_DATADIR} (需挂载宿主机数据目录)"
    fi
    
    mkdir -p "${BACKUP_DIR}"
    
    local BACKUP_SUBDIR="${BACKUP_DIR}/${CLUSTER_NAME}-physical-${TIMESTAMP}"
    
    log "数据目录: ${MYSQL_DATADIR}"
    log "备份目录: ${BACKUP_SUBDIR}"
    
    # xtrabackup 参数:
    # --backup: 备份模式
    # --target-dir: 备份目标目录
    # --datadir: MySQL 数据目录
    # --host/port/user/password: 连接信息(用于获取binlog位置)
    xtrabackup --backup \
        --target-dir="${BACKUP_SUBDIR}" \
        --datadir="${MYSQL_DATADIR}" \
        --host="${MYSQL_HOST}" \
        --port="${MYSQL_PORT}" \
        --user="${MYSQL_USER}" \
        --password="${MYSQL_PASSWORD}" \
        2>&1 | tee "${BACKUP_SUBDIR}/xtrabackup.log"
    
    # 压缩备份
    log "压缩物理备份..."
    cd "${BACKUP_DIR}"
    tar -czf "${CLUSTER_NAME}-physical-${TIMESTAMP}.tar.gz" "$(basename "${BACKUP_SUBDIR}")"
    rm -rf "${BACKUP_SUBDIR}"
    
    local BACKUP_SIZE=$(du -h "${CLUSTER_NAME}-physical-${TIMESTAMP}.tar.gz" | cut -f1)
    log "物理备份完成: ${BACKUP_DIR}/${CLUSTER_NAME}-physical-${TIMESTAMP}.tar.gz (大小: ${BACKUP_SIZE})"
}

# ==================== 清理旧备份 ====================
cleanup_old_backups() {
    log "清理 ${RETENTION_DAYS} 天前的旧备份..."
    
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type f -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type f -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
    
    log "旧备份清理完成"
}

# ==================== 主流程 ====================
main() {
    log "========================================"
    log "MySQL 备份开始"
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
    log "MySQL 备份完成"
    log "备份位置: ${BACKUP_DIR}"
    log "========================================"
}

main "$@"
