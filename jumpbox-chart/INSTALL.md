# Jumpbox 部署指南

## 前置条件

- Kubernetes 集群（1.24+，CronJob `timeZone` 需 1.27+ 稳定）
- Helm 3.x
- 至少一个可作为跳板机的节点
- 目标数据库集群（MySQL / PostgreSQL / Redis）已就绪

## 步骤 1：节点打标签

跳板机通过节点亲和性 `application/jumpbox=true` 调度。多副本会分散到不同节点（Pod 反亲和性），因此需要给 **≥ 副本数** 个节点打标签。

```bash
# 查看节点
kubectl get nodes

# 打标签（每个目标节点执行）
kubectl label node <node-name> application/jumpbox=true

# 验证
kubectl get nodes -l application/jumpbox=true
```

> 若只打了 1 个节点标签但副本数为 2，第二个 Pod 会因反亲和性 Pending。请保证标签节点数 ≥ replicaCount，或调低 replicaCount。

## 步骤 2：准备配置

```bash
cp jumpbox-chart/values-custom.yaml my-values.yaml
```

编辑 `my-values.yaml`，填入实际数据库地址与凭证：

```yaml
databases:
  mysql:
    enabled: true
    host: "mysql-cluster-haproxy.database.svc.cluster.local"
    port: 3306
    auth:
      username: root
      password: "实际密码"
  postgres:
    enabled: true
    host: "pg-cluster-primary.database.svc.cluster.local"
    port: 5432
    auth:
      username: postgres
      password: "实际密码"
      database: postgres
  redis:
    enabled: true
    host: "redis-cluster.database.svc.cluster.local"
    port: 6379
    auth:
      password: "实际密码"
```

### 凭证管理方式

Chart 支持两种凭证提供方式，**生产环境强烈建议使用 existingSecret**，避免密码明文出现在 values 文件或 Helm release 历史中。

| 方式 | 适用 | 说明 |
|------|------|------|
| `existingSecret` | 生产（推荐） | 引用预先创建的 K8s Secret，values 无明文 |
| `auth.password` | 测试/开发 | 明文写在 values，由 Chart 生成 Secret |

> 校验规则：数据库 `enabled: true` 但 `existingSecret` 和 `auth.password` 均为空时，`helm` 会直接报错拒绝渲染，防止误建空密码 Secret。

#### 使用 existingSecret（推荐生产环境）

现成的生产示例见 `jumpbox-chart/values-production.yaml`。步骤：

```bash
# 1. 预先创建凭证 Secret（一次性，可用运维专用流程管理）
kubectl create secret generic jumpbox-db-secret -n jumpbox \
  --from-literal=mysql-password='真实MySQL密码' \
  --from-literal=postgres-password='真实PG密码' \
  --from-literal=redis-password='真实Redis密码'

# 2. 部署时引用（values 中不含任何明文）
helm install jumpbox ./jumpbox-chart -n jumpbox --create-namespace \
  -f jumpbox-chart/values-production.yaml
```

values 中的引用写法：

```yaml
databases:
  mysql:
    existingSecret: "jumpbox-db-secret"
    existingSecretPasswordKey: "mysql-password"
    auth:
      username: root
      # password 留空
```

设置 `existingSecret` 后，Chart 不会为该库生成明文 Secret，密码直接从引用的 Secret 注入容器环境变量。

> 每个库可引用不同的 Secret，也可共用同一个 Secret 的不同 key（如上例三库共用 `jumpbox-db-secret`）。

## 步骤 3：部署

```bash
# 校验渲染
helm lint ./jumpbox-chart
helm template jumpbox ./jumpbox-chart -n jumpbox -f my-values.yaml

# 安装
helm install jumpbox ./jumpbox-chart -n jumpbox --create-namespace -f my-values.yaml

# 升级
helm upgrade jumpbox ./jumpbox-chart -n jumpbox -f my-values.yaml

# 卸载
helm uninstall jumpbox -n jumpbox
```

## 步骤 4：验证

```bash
# Pod 状态
kubectl get pods -n jumpbox -l app.kubernetes.io/instance=jumpbox

# 进入跳板机
kubectl exec -it -n jumpbox jumpbox-0 -- zsh
```

在跳板机内：

```bash
# 查看连接信息
db-connect info

# 连接数据库
db-connect mysql
db-connect postgres
db-connect redis

# kubectl 节点操作
kubectl get nodes
kubectl top nodes

# 手动备份
backup-all
```

## 备份说明

### 备份模式（backup.mode）

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `logical` | mysqldump / pg_dump / redis-cli --rdb | 远程网络备份（默认，推荐） |
| `physical` | xtrabackup / pgbackrest / 复制数据文件 | Pod 与 DB 同节点且挂载数据目录 |
| `both` | 逻辑 + 物理 | 两者都需要 |

> 物理备份需要访问数据库的本地数据文件。跳板机通过网络连接远程数据库时，物理备份要求 Pod 与数据库调度到**同一节点**，并将数据库数据目录挂载到 `datadir` 指定路径。纯远程场景请用 `logical`。

### 备份产物

```
/data/backups/
├── mysql/<时间戳>/mysql-cluster-logical-*.sql.gz
├── postgres/<时间戳>/pg-cluster-*.dump
└── redis/<时间戳>/redis-cluster-*.rdb.gz
```

### 定时备份

由 CronJob 执行（默认每天 2:00，Asia/Shanghai）。查看：

```bash
kubectl get cronjob -n jumpbox
kubectl get jobs -n jumpbox
# 查看某次备份日志
kubectl logs -n jumpbox job/<job-name>
```

手动触发一次定时备份：

```bash
kubectl create job -n jumpbox --from=cronjob/jumpbox-backup manual-backup-$(date +%s)
```

## 常见问题

**Q: Pod 一直 Pending？**
检查节点标签数量是否 ≥ 副本数：`kubectl get nodes -l application/jumpbox=true`。

**Q: 数据库连不上？**
在 Pod 内 `db-connect info` 确认地址，`nc -zv <host> <port>` 测试连通性。因启用 hostNetwork，DNS 使用 `ClusterFirstWithHostNet`。

**Q: 物理备份失败？**
确认 Pod 与 DB 同节点，且数据目录已通过 `extraHostVolumeMounts` 挂载到 `datadir` 路径。

**Q: 宿主机日志在哪看？**
挂载在容器内 `/host/var/log`（只读）。
