#!/bin/bash
# ============================================================
# CORDYS 安装/升级脚本 (install.sh)
# 用于在系统中安装或升级 CORDYS 平台，包括 Docker 及 Compose
# ============================================================

# 获取脚本所在目录
__current_dir=$(
   cd "$(dirname "$0")"
   pwd
)
# 转发所有参数
args=$@
# 操作系统信息
__os=$(uname -a)

# 日志函数：输出信息并追加到安装日志
function log() {
   message="[CORDYS Log]: $1"
   echo -e "${message}" 2>&1 | tee -a ${__current_dir}/install.log
}

# 环境变量自动导出
set -a
# 获取本机 IP
__local_ip=$(hostname -I | cut -d" " -f1)
# 加载安装配置
source ${__current_dir}/install.conf

# 判断安装类型（install 或 upgrade）
export INSTALL_TYPE='install'
if [ -f ~/.cordysrc ]; then
  source ~/.cordysrc > /dev/null
  echo "检测到已安装 CORDYS，安装目录 ${CORDYS_BASE}/cordys，执行升级流程"
  INSTALL_TYPE='upgrade'
elif [ -f /usr/local/bin/crmctl ]; then
  CORDYS_BASE=$(grep -oP '(?<=CORDYS_BASE=).*' /usr/local/bin/crmctl)
  echo "检测到已安装 CORDYS，安装目录 ${CORDYS_BASE}/cordys，执行升级流程"
  INSTALL_TYPE='upgrade'
else
  CORDYS_BASE=$(grep -oP '(?<=CORDYS_BASE=).*' ${__current_dir}/install.conf)
  echo "安装目录为 ${CORDYS_BASE}/cordys，开始新安装"
  INSTALL_TYPE='install'
fi

# 读取当前与目标版本，转换为可比较数字格式
__current_version=$(cat ${CORDYS_BASE}/cordys/version 2>/dev/null || echo "")
__target_version=$(cat ${__current_dir}/cordys/version)
current_version=${__current_version#v}
target_version=${__target_version#v}

IFS='.' read -r -a current_parts <<< "$current_version"
IFS='.' read -r -a target_parts <<< "$target_version"
current_numeric=$(printf '1%02d%02d%02d' ${current_parts[@]})
target_numeric=$(printf '1%02d%02d%02d' ${target_parts[@]})

# 不支持降级
if [[ ${current_numeric} -gt ${target_numeric} ]]; then
  echo -e "\e[31m检测到新版本低于当前版本，不支持降级\e[0m"
  exit 2
fi

# LTS 与非 LTS 切换提示
if [[ ${__current_version} =~ lts ]] && [[ ! ${__target_version} =~ lts ]]; then
  log "从 LTS 升级至非 LTS，包含实验性功能，请备份数据"
  read -p "是否继续升级? [n/y] " choice
  [[ ! $choice =~ ^[Yy]$ ]] && { echo "升级已取消"; exit; }
elif [[ ${INSTALL_TYPE} == "upgrade" && ${__target_version} =~ lts && ! ${__current_version} =~ lts ]]; then
  log "升级至 LTS 后仅能自动升级 LTS，升级非 LTS 需手动执行"
  read -p "是否继续升级? [n/y] " choice
  [[ ! $choice =~ ^[Yy]$ ]] && { echo "升级已取消"; exit; }
fi

log "开始拷贝安装文件"
# 创建目录并复制文件
mkdir -p ${CORDYS_BASE}/cordys
cp -f ./cordys/version ${CORDYS_BASE}/cordys/version
cp -rv --suffix=$(date +%Y%m%d-%H%M) ./cordys ${CORDYS_BASE}/cordys

# 保存安装路径
echo "CORDYS_BASE=${CORDYS_BASE}" > ~/.cordysrc
# 安装 crmctl 管理脚本
cp crmctl /usr/local/bin/crmctl && chmod +x /usr/local/bin/crmctl
ln -sf /usr/local/bin/crmctl /usr/bin/crmctl

log "======================= 开始安装 ======================="
# 安装 Docker 与 Docker Compose

# 检查 Docker
if command -v docker >/dev/null; then
  log "检测到 Docker，跳过安装并启动"
  service docker start | tee -a ${__current_dir}/install.log
else
  if [[ -d docker ]]; then
    log "使用离线包安装 Docker"
    cp docker/bin/* /usr/bin/
    cp docker/service/docker.service /etc/systemd/system/
    service docker start | tee -a ${__current_dir}/install.log
  else
    log "在线安装 Docker"
    curl -fsSL https://resource.fit2cloud.com/get-docker-linux.sh -o get-docker.sh
    sh get-docker.sh | tee -a ${__current_dir}/install.log
    service docker start | tee -a ${__current_dir}/install.log
  fi
fi

# 校验 Docker 运行状态
if ! docker ps >/dev/null 2>&1; then
  log "Docker 未正常运行，请检查后重试"
  exit 1
fi

# 检查 Docker Compose
if ! command -v docker-compose >/dev/null; then
  if [[ -d docker ]]; then
    log "离线安装 Docker Compose"
    cp docker/bin/docker-compose /usr/bin/
    chmod +x /usr/bin/docker-compose
  else
    log "在线安装 Docker Compose"
    curl -L https://resource.fit2cloud.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  fi
fi
# 验证 Compose 安装
if ! docker-compose version >/dev/null 2>&1; then
  log "docker-compose 安装或运行异常，请检查后重试"
  exit 1
fi

# 配置环境变量文件
cp -f ${__current_dir}/install.conf ${CORDYS_BASE}/cordys/install.conf.example
# 合并及保留用户配置
source ${__current_dir}/install.conf
source ~/.cordysrc >/dev/null
# 保存镜像标签并生成 .env
__ms_image_tag=${CORDYS_IMAGE_TAG}
env | grep CORDYS_ > ${CORDYS_BASE}/cordys/.env
ln -sf ${CORDYS_BASE}/cordys/.env ${CORDYS_BASE}/cordys/install.conf
# 确保主机名解析
grep -q "127.0.0.1 $(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" >> /etc/hosts

# 生成 Compose 文件并验证配置
crmctl generate_compose_files
crmctl config >/dev/null 2>&1 || { crmctl config; log "配置文件或版本不兼容，请检查 docker-compose 版本或配置"; exit 1; }

# 重定向日志到 install.log 并启用严格模式
exec > >(tee -a ${__current_dir}/install.log) 2>&1
set -e
export COMPOSE_HTTP_TIMEOUT=180
cd ${__current_dir}

# 加载或拉取镜像
if [[ -d images ]]; then
  log "加载本地镜像"
  for img in images/*; do docker load -i "$img"; done
else
  log "拉取远程镜像"
  crmctl pull
  curl -sfL https://resource.fit2cloud.com/installation-log.sh | sh -s ms ${INSTALL_TYPE} ${CORDYS_IMAGE_TAG}
fi

# 启动 CORDYS 服务
log "启动服务"
crmctl down -v
crmctl up -d --remove-orphans
crmctl status

echo -e "======================= 安装完成 =======================\n"
echo -e "访问方式: http://\$__local_ip:\${CORDYS_SERVER_PORT}\n用户名: admin\n初始密码: CordysCRM"
echo -e "使用 'crmctl status' 查看服务状态。\n"
