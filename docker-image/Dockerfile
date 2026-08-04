#############################
#     设置公共的变量         #
#############################
ARG BASE_IMAGE_TAG=resolute
FROM ubuntu:${BASE_IMAGE_TAG}

# 作者描述信息
LABEL org.opencontainers.image.authors="iflyelf" \
      org.opencontainers.image.vendor="iflyelf"

ARG TARGETARCH
ARG TARGETVARIANT

# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 镜像变量
ARG DOCKER_IMAGE=iflyelf/jumpbox
ENV DOCKER_IMAGE=$DOCKER_IMAGE
ARG DOCKER_IMAGE_OS=ubuntu
ENV DOCKER_IMAGE_OS=$DOCKER_IMAGE_OS
ARG DOCKER_IMAGE_TAG=resolute
ENV DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG

# 环境设置
ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=$DEBIAN_FRONTEND

# GO环境变量
ARG GO_VERSION=1.26.4
ENV GO_VERSION=$GO_VERSION
ARG GOROOT=/opt/go
ENV GOROOT=$GOROOT
ARG GOPATH=/opt/golang
ENV GOPATH=$GOPATH
# Go 模块代理(加速依赖下载, 国内构建必备; 海外可改为 https://proxy.golang.org,direct)
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=$GOPROXY

ARG PKG_DEPS="\
    zsh \
    bash \
    bash-doc \
    bash-completion \
    conntrack \
    ipset \
    ipvsadm \
    bind9-dnsutils \
    iproute2 \
    net-tools \
    iptables \
    bridge-utils \
    openvswitch-switch \
    libseccomp2 \
    nfs-common \
    rsync \
    socat \
    psmisc \
    procps \
    sysstat \
    firewalld \
    chrony \
    ntpsec-ntpdate \
    tcpdump \
    telnet \
    lsof \
    iftop \
    htop \
    nmap \
    nmap-common \
    jq \
    curl \
    wget \
    axel \
    git \
    vim \
    tree \
    unzip \
    zip \
    tar \
    subversion \
    lrzsz \
    gcc \
    g++ \
    build-essential \
    binutils \
    autoconf \
    automake \
    libtool \
    gettext \
    autopoint \
    asciidoc \
    gawk \
    patch \
    flex \
    texinfo \
    device-tree-compiler \
    zlib1g-dev \
    libjpeg-dev \
    libelf-dev \
    libssl-dev \
    openssl \
    libffi-dev \
    libglib2.0-dev \
    xmlto \
    libncurses-dev \
    locate \
    lvm2 \
    rsyslog \
    ca-certificates \
    gnupg2 \
    debsums \
    locales \
    tzdata \
    fonts-droid-fallback \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    fonts-arphic-ukai \
    fonts-arphic-uming \
    language-pack-zh-hans \
    numactl \
    xz-utils \
    libaio-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-yaml \
    python3-venv \
    python-is-python3 \
    supervisor \
    tini \
    sshpass \
    iputils-ping \
    ncat \
    upx-ucl \
    libxml2-dev \
    libxslt1-dev \
    cargo \
    rustc \
    sudo \
    npm \
    uglifyjs"
ENV PKG_DEPS=$PKG_DEPS

# ***** 安装依赖 *****
RUN set -eux && \
   # 更新源地址
   sed -i 's@URIs: http://[a-z.]*\.ubuntu\.com/ubuntu/@URIs: https://mirrors.aliyun.com/ubuntu/@g' /etc/apt/sources.list.d/ubuntu.sources && \
   sed -i 's@^Types: deb$@Types: deb deb-src@' /etc/apt/sources.list.d/ubuntu.sources && \
   # 解决证书认证失败问题
   touch /etc/apt/apt.conf.d/99verify-peer.conf && echo >>/etc/apt/apt.conf.d/99verify-peer.conf "Acquire { https::Verify-Peer false }" && \
   # 更新系统软件
   DEBIAN_FRONTEND=noninteractive apt-get update -qqy && apt-get upgrade -qqy && \
   # 安装依赖包
   DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends $PKG_DEPS --option=Dpkg::Options::=--force-confdef && \
   # multilib/i386 交叉编译包仅 amd64 架构提供, 其他架构跳过
   if [ "${TARGETARCH}" = "amd64" ]; then \
       DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
           gcc-multilib g++-multilib libc6-dev-i386 --option=Dpkg::Options::=--force-confdef ; \
   fi && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoremove --purge && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoclean && \
   rm -rf /var/lib/apt/lists/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   # 更新时间
   echo ${TZ} > /etc/timezone && \
   # 更改为zsh
   sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true && \
   sed -i -e "s/bin\/ash/bin\/zsh/" /etc/passwd && \
   # vim 默认配置文件存在时才关闭 mouse(不同版本路径不同, 用 find 定位)
   find /usr/share/vim -name defaults.vim -exec sed -i -e 's/mouse=/mouse-=/g' {} + && \
   locale-gen zh_CN.UTF-8 && localedef -f UTF-8 -i zh_CN zh_CN.UTF-8 && locale-gen

# ***** 安装 Node.js 最新 LTS（每次构建时安装当前最新版本）*****
# 使用 n 在构建时获取最新 LTS；若需最新 Current 可改为 n latest
RUN set -eux && \
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
   DEBIAN_FRONTEND=noninteractive apt-get update -qqy && \
   DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends nodejs && \
   npm config set registry https://registry.npmmirror.com && \
   npm install -g n && \
   n lts && \
   npm install -g wrangler && \
   rm -rf /var/lib/apt/lists/* /tmp/*

# ***** 安装 python3 版本 *****
RUN set -eux && \
    python3 -m pip config set global.break-system-packages true && \
    pip3 config set global.index-url http://mirrors.aliyun.com/pypi/simple/ && \
    pip3 config set install.trusted-host mirrors.aliyun.com && \
    python3 -m pip install --no-cache-dir --ignore-installed setuptools wheel cython && \
    python3 -m pip install --no-cache-dir pycryptodome lxml cython beautifulsoup4 requests && \
    rm -rf /tmp/* /var/lib/apt/lists/*

# ***** 安装golang *****
RUN set -eux && \
    # 映射 buildx TARGETARCH 到 Go 官方包名 (arm -> armv6l, 其他直接用)
    case "${TARGETARCH}" in \
        amd64)   GO_ARCH=amd64   ;; \
        arm64)   GO_ARCH=arm64   ;; \
        arm)     GO_ARCH=armv6l  ;; \
        386)     GO_ARCH=386     ;; \
        *)       echo "不支持的架构: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "目标架构: ${TARGETARCH} => Go 包: linux-${GO_ARCH}" && \
    wget --no-check-certificate https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz \
         -O /tmp/go-${GO_ARCH}.tar.gz && \
    tar xzf /tmp/go-${GO_ARCH}.tar.gz -C /opt && \
    mkdir -pv ${GOPATH}/bin && \
    # 仅删除 Go 压缩包, 不清空整个 /tmp (避免误删 DOWNLOAD_SRC=/tmp/src)
    rm -f /tmp/go-${GO_ARCH}.tar.gz && \
    # 软链 go 到 /usr/bin, 后续 RUN 层无需配 PATH
    ln -sf /opt/go/bin/* /usr/bin/ && \
    # 加载环境变量
    export GOROOT=/opt/go && \
    export GOPATH=/opt/golang && \
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin && \
    # 创建目录并清理文件
    mkdir -pv $GOPATH/bin && rm -rf /tmp/* /var/lib/apt/lists/* && \
    # 验证版本
    go version

#############################################################
#  以下为跳板机(jumpbox)扩展层: 数据库客户端/备份/K8s工具/Ansible  #
#############################################################

# 数据库版本变量(与集群版本匹配)
# MySQL: 匹配 Percona Server 8.4.x
ARG MYSQL_PXB_MAJOR=84
ENV MYSQL_PXB_MAJOR=$MYSQL_PXB_MAJOR
# PostgreSQL: 匹配 PG 18.x
ARG PG_MAJOR=18
ENV PG_MAJOR=$PG_MAJOR
ENV PATH=$PATH:/usr/lib/postgresql/$PG_MAJOR/bin

# ***** 安装数据库客户端 (MySQL / PostgreSQL / Redis) *****
RUN set -eux && \
    apt-get update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends lsb-release gnupg2 ca-certificates wget curl && \
    # --- PostgreSQL 官方 PGDG 源 (匹配 PG 18) ---
    install -d /usr/share/postgresql-common/pgdg && \
    wget --no-check-certificate -O /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    # --- Percona 源 ---
    # pdps-8.0: Percona Distribution for MySQL 8.0 (提供 percona-server-client)
    # ppg-18:   Percona Distribution for PostgreSQL 18
    # tools:    备份工具 (percona-xtrabackup-80 / percona-pgbackrest / mydumper)
    # 注意: Percona 8.4 尚无独立仓库, 用 8.0 客户端兼容
    wget --no-check-certificate https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb -O /tmp/percona-release.deb && \
    dpkg -i /tmp/percona-release.deb && rm -f /tmp/percona-release.deb && \
    percona-release enable pdps-8.0 release && \
    percona-release enable tools release && \
    percona-release enable ppg-${PG_MAJOR} release || true && \
    # --- Redis 客户端源 (redis.io 官方) ---
    # 注意: redis.io 的 gpg 是 ASCII armored 格式, 新版 apt 要求二进制, 需 gpg --dearmor 转换
    # redis.io 源以 Debian/Ubuntu 稳定版 codename 命名, 开发版(如 resolute)可能无对应仓库,
    # 通过 REDIS_CODENAME 回退到最近的 LTS codename (noble)
    REDIS_CODENAME="$(lsb_release -cs)" && \
    if ! curl -fsSL "https://packages.redis.io/deb/dists/${REDIS_CODENAME}/InRelease" >/dev/null 2>&1; then \
        echo "Redis 源无 ${REDIS_CODENAME} 仓库, 回退到 noble" && REDIS_CODENAME=noble ; \
    fi && \
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${REDIS_CODENAME} main" > /etc/apt/sources.list.d/redis.list && \
    # --- 更新并安装客户端 ---
    apt-get update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
        percona-server-client \
        postgresql-client-${PG_MAJOR} \
        redis-tools && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# ***** 安装数据库备份工具 (xtrabackup / pgbackrest / mydumper) *****
RUN set -eux && \
    apt-get update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
        percona-xtrabackup-${MYSQL_PXB_MAJOR} \
        percona-pgbackrest \
        mydumper && \
    rm -rf /var/lib/apt/lists/* /tmp/* && \
    # 验证备份工具
    xtrabackup --version && \
    pgbackrest version

# ***** 安装 K8s 工具 (kubectl / helm / helmfile, GitHub API 获取最新稳定版) *****
RUN set -eux && \
    # 架构映射
    case "${TARGETARCH}" in \
        amd64) K8S_ARCH=amd64 ;; \
        arm64) K8S_ARCH=arm64 ;; \
        arm)   K8S_ARCH=arm   ;; \
        *)     echo "不支持的架构: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    # --- kubectl (官方 stable 通道) ---
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" && \
    echo "kubectl 版本: ${KUBECTL_VERSION}" && \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl" && \
    chmod +x /usr/local/bin/kubectl && \
    # --- helm (GitHub API 最新稳定版) ---
    HELM_VERSION="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')" && \
    echo "helm 版本: ${HELM_VERSION}" && \
    curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${K8S_ARCH}.tar.gz" && \
    tar -zxf /tmp/helm.tar.gz -C /tmp && \
    mv /tmp/linux-${K8S_ARCH}/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    # --- helmfile (GitHub API 最新稳定版) ---
    HELMFILE_TAG="$(curl -fsSL https://api.github.com/repos/helmfile/helmfile/releases/latest | jq -r '.tag_name')" && \
    HELMFILE_VERSION="${HELMFILE_TAG#v}" && \
    echo "helmfile 版本: ${HELMFILE_VERSION}" && \
    curl -fsSL -o /tmp/helmfile.tar.gz "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_TAG}/helmfile_${HELMFILE_VERSION}_linux_${K8S_ARCH}.tar.gz" && \
    tar -zxf /tmp/helmfile.tar.gz -C /tmp helmfile && \
    mv /tmp/helmfile /usr/local/bin/helmfile && \
    chmod +x /usr/local/bin/helmfile && \
    # --- helm 插件 (diff, 供 helmfile 使用) ---
    helm plugin install https://github.com/databus23/helm-diff || true && \
    # 清理
    rm -rf /tmp/* && \
    # 验证
    kubectl version --client && \
    helm version && \
    helmfile version

# ***** 安装 Ansible 及配置 *****
RUN set -eux && \
    apt-get update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
        python3 python-is-python3 python3-pip sshpass && \
    python3 -m pip install --break-system-packages --no-cache-dir ansible && \
    rm -rf /var/lib/apt/lists/* /tmp/* && \
    # Ansible 配置
    mkdir -pv /etc/ansible && \
    printf '%s\n' \
    '[defaults]' \
    '# 传输模式' \
    'gathering = smart' \
    '# 超时时间' \
    'gather_timeout = 10' \
    '# 最大进程数' \
    'forks=30' \
    '# 是否检查SSH key' \
    'host_key_checking = False' \
    '# 是否展示跳过的主机的信息' \
    'display_skipped_hosts = False' \
    '# 是否展示警告信息' \
    'deprecation_warnings = False' \
    '# 是否展示命令警告信息' \
    'command_warnings = False' \
    '# python版本' \
    'interpreter_python = /usr/bin/python' \
    '# 启用 Ansible 自带的回调插件' \
    'bin_ansible_callbacks = True' \
    '# 使用默认回调插件并设置 YAML 格式输出' \
    'stdout_callback = ansible.builtin.default' \
    '# 设置输出格式为 YAML' \
    'result_format = yaml' \
    '# 彩色输出' \
    'force_color = True' \
    '' \
    '[ssh_connection]' \
    '# 连接ssh参数设置' \
    'ssh_args = -o ControlMaster=auto -o ControlPersist=3s -o ServerAliveInterval=3 -o ServerAliveCountMax=5' \
    'control_path = /tmp/ansible-ssh-%%h-%%p-%%r' \
    '# 减少ssh连接次数' \
    'pipelining = True' \
    '# 在需要时自动切换到 scp' \
    'scp_if_ssh = smart' \
    '# 在传输文件时智能选择 sftp 或 scp' \
    'transfer_method = smart' \
    > /etc/ansible/ansible.cfg && \
    # pip 配置
    mkdir -pv /root/.pip && \
    printf '%s\n' \
    '[global]' \
    'timeout = 6000' \
    'index-url = http://mirrors.aliyun.com/pypi/simple/' \
    'trusted-host = mirrors.aliyun.com' \
    > /root/.pip/pip.conf

# ***** 拷贝备份/连接脚本 *****
COPY scripts/ /opt/jumpbox/scripts/
RUN set -eux && \
    chmod +x /opt/jumpbox/scripts/*.sh && \
    ln -sf /opt/jumpbox/scripts/db-connect.sh /usr/local/bin/db-connect && \
    ln -sf /opt/jumpbox/scripts/backup-all.sh /usr/local/bin/backup-all && \
    ln -sf /opt/jumpbox/scripts/backup-mysql.sh /usr/local/bin/backup-mysql && \
    ln -sf /opt/jumpbox/scripts/backup-postgres.sh /usr/local/bin/backup-postgres && \
    ln -sf /opt/jumpbox/scripts/backup-redis.sh /usr/local/bin/backup-redis && \
    # 创建备份目录
    mkdir -pv /data/backups/mysql /data/backups/postgres /data/backups/redis

# ***** 工作目录 *****
WORKDIR /root

# ***** 使用 tini 作为 init, 保持容器常驻(跳板机) *****
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
