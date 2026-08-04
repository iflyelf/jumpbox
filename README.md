# Jumpbox K8s 跳板机

基于 [ubuntu-docker](https://github.com/iflyelf/ubuntu-docker) 模板扩展的 K8s 跳板机镜像 + Helm Chart。集成数据库客户端、备份工具、K8s 运维工具，以特权模式运行，用作集群内的运维跳板机与数据库备份节点。

## 功能特性

- **数据库客户端**：MySQL 8.4（Percona）、PostgreSQL 18、Redis
- **备份工具**：
  - 逻辑备份：`mysqldump`、`pg_dump`、`redis-cli --rdb`、`mydumper`
  - 物理备份：`xtrabackup`（MySQL 8.4）、`pgbackrest`（PG）
- **K8s 工具**：`kubectl`、`helm`、`helmfile`（构建时通过 GitHub API 拉取最新稳定版）
- **运维工具**：`ansible`、`sshpass` 及完整的 ubuntu-docker 基础工具链
- **集群运维**：内置 RBAC（ClusterRole），`kubectl` 可跨**所有命名空间**操作节点与工作负载（cordon/drain/label/taint、Pod exec/删除、扩缩容等），可选 `clusterAdmin` 完全管理员模式
- **定时备份**：CronJob 定时逻辑/物理备份，自动清理过期备份
- **宿主机挂载**：挂载宿主机 `/data`（备份数据）与 `/var/log`（只读日志查看）

## 目录结构

```
jumpbox/
├── docker-image/                  # 镜像构建
│   ├── Dockerfile                 # 基于 ubuntu-docker 模板扩展
│   ├── .github/workflows/
│   │   └── docker-publish.yml     # 多架构构建并推送 DockerHub
│   └── scripts/                   # 内置脚本
│       ├── backup-mysql.sh        # MySQL 备份 (逻辑/物理)
│       ├── backup-postgres.sh     # PostgreSQL 备份 (逻辑/物理)
│       ├── backup-redis.sh        # Redis 备份 (逻辑/物理)
│       ├── backup-all.sh          # 统一备份调度
│       └── db-connect.sh          # 交互式连接助手
└── jumpbox-chart/                 # Helm Chart
    ├── Chart.yaml
    ├── values.yaml
    ├── values-custom.yaml         # 自定义配置示例
    └── templates/
        ├── _helpers.tpl
        ├── statefulset.yaml       # 多副本 StatefulSet
        ├── service.yaml
        ├── serviceaccount.yaml
        ├── rbac.yaml              # 节点操作权限
        ├── secret.yaml            # 数据库凭证
        ├── configmap-scripts.yaml # 备份脚本入口
        ├── pv.yaml                # hostPath 本地 PV
        ├── cronjob-backup.yaml    # 定时备份
        └── NOTES.txt
```

## 镜像构建

镜像通过 GitHub Action 自动构建并推送到 `iflyelf/jumpbox`（多架构 `linux/amd64,linux/arm64`）。

需在仓库配置 Secrets：`DOCKER_USERNAME`、`DOCKER_PASSWORD`。

本地构建（可选）：

```bash
cd docker-image
docker build -t iflyelf/jumpbox:latest .
```

## 版本匹配

镜像内客户端/备份工具版本与目标集群对齐：

| 组件 | 集群版本 | 客户端 / 备份工具 |
|------|---------|------------------|
| MySQL | Percona Server 8.4.x | `percona-server-client` + `percona-xtrabackup-84` |
| PostgreSQL | 18.x | `postgresql-client-18` + `percona-pgbackrest` |
| Redis | 8.2.x | `redis-tools` |

通过 Dockerfile 的 `ARG MYSQL_PXB_MAJOR` / `ARG PG_MAJOR` 可调整版本。

## 快速部署

详见 [INSTALL.md](INSTALL.md)。

```bash
# 1. 给跳板机节点打标签
kubectl label node <node-name> application/jumpbox=true

# 2. 复制并修改配置
cp jumpbox-chart/values-custom.yaml my-values.yaml

# 3. 部署
helm install jumpbox ./jumpbox-chart -n jumpbox --create-namespace -f my-values.yaml
```

## 安全说明

本 Chart 默认以**最高权限**运行：`privileged: true`、`hostNetwork`、`hostPID`、`hostIPC`、`capabilities: ALL`、`runAsUser: 0`。这是跳板机场景的预期配置，但会绕过容器隔离。

**RBAC 权限**：默认 ClusterRole 授予**跨所有命名空间**的节点、Pod、工作负载完整操作权限（细粒度规则）。可通过 `rbac.clusterAdmin: true` 启用完全管理员模式（等价 cluster-admin，所有资源所有操作）。

**安全建议**：
- 限制跳板机 Pod 所在命名空间（jumpbox）的访问权限，仅授予运维人员
- 仅在受信任的运维节点部署
- 生产环境必须用 `existingSecret` 管理数据库凭证（见下方）

### 凭证管理

- **生产环境使用 `existingSecret`**：预先创建 K8s Secret 并引用，values 中不出现明文密码。示例见 `jumpbox-chart/values-production.yaml`。
- 明文 `auth.password` 方式仅用于测试/开发（`values-custom.yaml`）。
- 数据库 `enabled` 但未提供 `existingSecret` 或 `auth.password` 时，`helm` 会直接报错，防止误建空密码 Secret。
- 设置 `existingSecret` 后，Chart 不为该库生成明文 Secret，凭证直接从引用的 Secret 注入。
