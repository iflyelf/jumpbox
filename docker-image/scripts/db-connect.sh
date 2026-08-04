#!/bin/bash
#=================================================
# 交互式数据库连接助手
# 作者: iflyelf
# 用法: db-connect [mysql|postgres|redis] [cluster-name]
#=================================================

set -uo pipefail

export TZ=Asia/Shanghai

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════╗"
    echo "║       Jumpbox 数据库连接助手          ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# ==================== MySQL 连接 ====================
connect_mysql() {
    local HOST="${MYSQL_HOST:-${1:-localhost}}"
    local PORT="${MYSQL_PORT:-3306}"
    local USER="${MYSQL_USER:-root}"
    local PASSWORD="${MYSQL_PASSWORD:-}"
    
    echo -e "${GREEN}连接 MySQL: ${HOST}:${PORT} (用户: ${USER})${NC}"
    
    if [ -n "${PASSWORD}" ]; then
        mysql -h "${HOST}" -P "${PORT}" -u "${USER}" -p"${PASSWORD}"
    else
        mysql -h "${HOST}" -P "${PORT}" -u "${USER}" -p
    fi
}

# ==================== PostgreSQL 连接 ====================
connect_postgres() {
    local HOST="${PG_HOST:-${1:-localhost}}"
    local PORT="${PG_PORT:-5432}"
    local USER="${PG_USER:-postgres}"
    local DATABASE="${PG_DATABASE:-postgres}"
    
    export PGPASSWORD="${PG_PASSWORD:-}"
    
    echo -e "${GREEN}连接 PostgreSQL: ${HOST}:${PORT} (用户: ${USER}, 数据库: ${DATABASE})${NC}"
    psql -h "${HOST}" -p "${PORT}" -U "${USER}" -d "${DATABASE}"
}

# ==================== Redis 连接 ====================
connect_redis() {
    local HOST="${REDIS_HOST:-${1:-localhost}}"
    local PORT="${REDIS_PORT:-6379}"
    local PASSWORD="${REDIS_PASSWORD:-}"
    
    echo -e "${GREEN}连接 Redis: ${HOST}:${PORT}${NC}"
    
    if [ -n "${PASSWORD}" ]; then
        redis-cli -h "${HOST}" -p "${PORT}" -a "${PASSWORD}" --no-auth-warning
    else
        redis-cli -h "${HOST}" -p "${PORT}"
    fi
}

# ==================== 显示连接信息 ====================
show_info() {
    echo -e "${YELLOW}当前配置的数据库连接信息:${NC}"
    echo ""
    echo -e "  MySQL:      ${MYSQL_HOST:-未配置}:${MYSQL_PORT:-3306} (${MYSQL_USER:-root})"
    echo -e "  PostgreSQL: ${PG_HOST:-未配置}:${PG_PORT:-5432} (${PG_USER:-postgres})"
    echo -e "  Redis:      ${REDIS_HOST:-未配置}:${REDIS_PORT:-6379}"
    echo ""
    echo -e "${YELLOW}可用命令:${NC}"
    echo "  db-connect mysql      - 连接 MySQL"
    echo "  db-connect postgres   - 连接 PostgreSQL"
    echo "  db-connect redis      - 连接 Redis"
    echo "  backup-mysql          - 执行 MySQL 备份"
    echo "  backup-postgres       - 执行 PostgreSQL 备份"
    echo "  backup-redis          - 执行 Redis 备份"
    echo "  backup-all            - 执行全部备份"
}

# ==================== 主入口 ====================
print_banner

DB_TYPE="${1:-}"

case "${DB_TYPE}" in
    mysql|m)
        connect_mysql "${2:-}"
        ;;
    postgres|pg|postgresql|p)
        connect_postgres "${2:-}"
        ;;
    redis|r)
        connect_redis "${2:-}"
        ;;
    info|"")
        show_info
        ;;
    *)
        echo -e "${RED}未知类型: ${DB_TYPE}${NC}"
        echo "用法: db-connect [mysql|postgres|redis|info]"
        exit 1
        ;;
esac
