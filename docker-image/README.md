# Jumpbox 镜像

基于 [ubuntu-docker](https://github.com/iflyelf/ubuntu-docker) 模板扩展，完整保留原基础镜像内容，追加数据库客户端、备份工具、K8s 运维工具与 Ansible。

## 已安装组件

### 数据库客户端
- `percona-server-client`（MySQL 8.4）
- `postgresql-client-18`
- `redis-tools`

### 备份工具
- `percona-xtrabackup-84`（MySQL 物理备份）
- `percona-pgbackrest`（PostgreSQL 物理备份）
- `mydumper`（MySQL 并行逻辑备份）

### K8s 工具（构建时经 GitHub API 拉取最新稳定版）
- `kubectl`
- `helm`（含 helm-diff 插件）
- `helmfile`

### 运维工具
- `ansible`（pip 安装）、`sshpass`
- ubuntu-docker 基础工具链（zsh、vim、git、python3、golang、node 等）

## 内置脚本

均已软链到 PATH：

| 命令 | 说明 |
|------|------|
| `db-connect [mysql\|postgres\|redis\|info]` | 交互式连接数据库 |
| `backup-mysql` | MySQL 备份 |
| `backup-postgres` | PostgreSQL 备份 |
| `backup-redis` | Redis 备份 |
| `backup-all` | 统一备份调度 |

脚本通过环境变量读取连接信息（`MYSQL_HOST`、`PG_HOST`、`REDIS_HOST` 等），由 Helm Chart 注入。

## 构建参数

| ARG | 默认 | 说明 |
|-----|------|------|
| `MYSQL_PXB_MAJOR` | `84` | xtrabackup / MySQL 客户端主版本 |
| `PG_MAJOR` | `18` | PostgreSQL 客户端主版本 |
| `TZ` | `Asia/Shanghai` | 时区 |

```bash
docker build -t iflyelf/jumpbox:latest .
docker build --build-arg PG_MAJOR=17 -t iflyelf/jumpbox:pg17 .
```

## 自动构建

仓库根目录 `.github/workflows/docker-publish.yml` 在以下情况触发多架构构建并推送 DockerHub：
- 修改 `docker-image/Dockerfile` 或 `docker-image/scripts/**`
- 手动触发 / Star

需配置仓库 Secrets：`DOCKER_USERNAME`、`DOCKER_PASSWORD`。
