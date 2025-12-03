#!/bin/bash

  __current_dir=$(
    cd "$(dirname "$0")" && pwd
  )
  # shellcheck disable=SC2034
  args=("$@")
  __os=$(uname -a)

  function log() {
    message="[Cordys CRM Log]: $1"
    echo -e "${message}" 2>&1 | tee -a "${__current_dir}/install.log"
  }

  set -a
  __local_ip=$(hostname -I | cut -d" " -f 1)
  source "${__current_dir}/install.conf"

  export INSTALL_TYPE='install'
  if [ -f ~/.cordysrc ]; then
    # shellcheck disable=SC1090
    source ~/.cordysrc >/dev/null 2>&1
    echo "检测到已安装的 Cordys CRM，安装目录：${CORDYS_BASE}/cordys，将执行升级流程。"
    INSTALL_TYPE='upgrade'
  elif [ -f /usr/local/bin/csctl ]; then
    CORDYS_BASE=$(grep -E '^[[:space:]]*CORDYS_BASE=' /usr/local/bin/csctl | awk -F= '{print $2}' 2>/dev/null)
    echo "检测到已安装的 Cordys CRM，安装目录：${CORDYS_BASE}/cordys，将执行升级流程。"
    INSTALL_TYPE='upgrade'
  else
    CORDYS_BASE=$(grep -E '^[[:space:]]*CORDYS_BASE=' "${__current_dir}/install.conf" | awk -F= '{print $2}' 2>/dev/null)
    echo "安装目录：${CORDYS_BASE}/cordys 开始执行全新安装。"
    INSTALL_TYPE='install'
  fi
  set +a

  __current_version=$(cat ${CORDYS_BASE}/cordys/version 2>/dev/null || echo "")
  __target_version=$(cat ${__current_dir}/cordys/version)

  # 截取实际版本
  current_version=${__current_version%-*}
  current_version=${current_version:1}
  target_version=${__target_version%-*}
  target_version=${target_version:1}

  # 使用 IFS 分割为数组（更安全的写法）
  IFS='.' read -r -a current_version_arr <<< "${current_version}"
  IFS='.' read -r -a target_version_arr <<< "${target_version}"

  current_version=$(printf '1%02d%02d%02d' "${current_version_arr[0]:-0}" "${current_version_arr[1]:-0}" "${current_version_arr[2]:-0}")
  target_version=$(printf '1%02d%02d%02d' "${target_version_arr[0]:-0}" "${target_version_arr[1]:-0}" "${target_version_arr[2]:-0}")

  if [[ "${current_version}" > "${target_version}" ]]; then
    echo -e "\e[31m检测到目标版本低于当前版本，禁止降级。\e[0m"
    exit 2
  fi

  log "正在复制安装文件到目标目录..."
  mkdir -p "${CORDYS_BASE}/cordys"
  cp -rv --suffix=".$(date +%Y%m%d-%H%M)" ./cordys "${CORDYS_BASE}/"

  # 记录安装路径
  echo "CORDYS_BASE=${CORDYS_BASE}" > ~/.cordysrc
  # 安装 csctl 命令
  cp csctl /usr/local/bin && chmod +x /usr/local/bin/csctl
  ln -s /usr/local/bin/csctl /usr/bin/csctl 2>/dev/null || true

  log "======================= 开始安装 ======================="
  # Install docker & docker-compose
  if command -v docker >/dev/null 2>&1; then
    log "已检测到 Docker，跳过安装步骤。"
    log "正在启动 Docker 服务..."
    service docker start 2>&1 | tee -a "${__current_dir}/install.log"
  else
    if [[ -d docker ]]; then
      log "正在离线安装 Docker..."
      chmod +x docker/bin/*
      cp docker/bin/* /usr/bin/
      cp docker/service/docker.service /etc/systemd/system/
      chmod 754 /etc/systemd/system/docker.service
      log "正在启动 Docker 服务..."
      service docker start 2>&1 | tee -a "${__current_dir}/install.log"
      log "... 设置 docker 开机自启动"
      systemctl enable docker 2>&1 | tee -a ${__current_dir}/install.log
    else
      log "正在在线安装 Docker..."
      curl -fsSL https://resource.fit2cloud.com/get-docker-linux.sh -o get-docker.sh 2>&1 | tee -a "${__current_dir}/install.log"
      sudo sh get-docker.sh 2>&1 | tee -a "${__current_dir}/install.log"
      log "正在启动 Docker 服务..."
      service docker start 2>&1 | tee -a "${__current_dir}/install.log"
      log "... 设置 docker 开机自启动"
      systemctl enable docker 2>&1 | tee -a ${__current_dir}/install.log
    fi
  fi

  # 检查 docker 服务是否正常运行
  docker ps >/dev/null 2>&1
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    log "Docker 服务未正常运行，请先安装并启动 Docker 后重试。"
    exit 1
  fi

  # 安装 docker-compose
  if command -v docker-compose >/dev/null 2>&1; then
    log "已检测到 Docker Compose，跳过安装步骤。"
  else
    if [[ -d docker ]]; then
      log "正在离线安装 Docker Compose..."
      cp docker/bin/docker-compose /usr/bin/
      chmod +x /usr/bin/docker-compose
    else
      log "正在在线安装 Docker Compose..."
      curl -L "https://resource.fit2cloud.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s | tr 'A-Z' 'a-z')-$(uname -m)" -o /usr/local/bin/docker-compose 2>&1 | tee -a "${__current_dir}/install.log"
      chmod +x /usr/local/bin/docker-compose
      ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
    fi
  fi

  # 检查 docker-compose 是否正常
  docker-compose version >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "Docker Compose 未正常安装，请先完成安装后重试。"
    exit 1
  fi

  # 将配置信息存储到安装目录的环境变量配置文件中
  echo '' >> "${CORDYS_BASE}/cordys/.env"

  # 通过加载环境变量的方式保留已修改的配置项，仅添加新增的配置项
  source "${__current_dir}/install.conf"
  # shellcheck disable=SC1090
  source ~/.cordysrc >/dev/null 2>&1 || true
  __cordys_image_tag=${CORDYS_IMAGE_TAG}
  # shellcheck source=/dev/null
  source "${CORDYS_BASE}/cordys/.env" >/dev/null 2>&1 || true

  export CORDYS_IMAGE_TAG="${__cordys_image_tag}"
  env | grep '^CORDYS_' > "${CORDYS_BASE}/cordys/.env"
  ln -s "${CORDYS_BASE}/cordys/.env" "${CORDYS_BASE}/cordys/install.conf" 2>/dev/null || true
  grep -q "127.0.0.1 $(hostname)" /etc/hosts >/dev/null 2>&1 || echo "127.0.0.1 $(hostname)" >> /etc/hosts

  # 提取 install.conf 中的 CORDYS_IMAGE_NAME 配置值
  CORDYS_IMAGE_NAME=$(grep -E '^CORDYS_IMAGE_NAME=' "${__current_dir}/install.conf" | cut -d '=' -f2-)

  # 如果在 install.conf 中找到了 CORDYS_IMAGE_NAME，更新 .env 文件
  if [ -n "${CORDYS_IMAGE_NAME}" ]; then
    if grep -q '^CORDYS_IMAGE_NAME=' "${CORDYS_BASE}/cordys/.env"; then
      sed -i "s/^CORDYS_IMAGE_NAME=.*/CORDYS_IMAGE_NAME=${CORDYS_IMAGE_NAME}/" "${CORDYS_BASE}/cordys/.env"
    else
      echo "CORDYS_IMAGE_NAME=${CORDYS_IMAGE_NAME}" >> "${CORDYS_BASE}/cordys/.env"
    fi
  fi

  csctl generate_compose_files

  exec > >(tee -a "${__current_dir}/install.log") 2>&1
  set -e
  export COMPOSE_HTTP_TIMEOUT=180
  cd "${__current_dir}"

  # 加载镜像
  if [[ -d images ]]; then
    log "正在加载离线镜像..."
    shopt -s nullglob
    for img in images/*; do
      [ -f "$img" ] || continue
      docker load -i "$img"
    done
    shopt -u nullglob
  else
    log "正在在线拉取镜像..."
    csctl pull
    curl -sfL https://resource.fit2cloud.com/installation-log.sh | sh -s cordys "${INSTALL_TYPE}" "${CORDYS_IMAGE_TAG}"
    cd - >/dev/null 2>&1 || true
  fi

  log "正在启动服务..."
  csctl down -v
  csctl up -d --remove-orphans

  csctl status

  echo -e "======================= 安装完成 =======================\n"
  echo -e "访问方式：\nURL： http://<服务器IP>:${CORDYS_SERVER_PORT}\n默认用户名：admin\n默认密码：CordysCRM"
  echo -e "可使用命令 \`csctl status\` 查看服务状态。\n"
