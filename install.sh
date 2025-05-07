#!/bin/bash

__current_dir=$(
   cd "$(dirname "$0")"
   pwd
)
args=$@
__os=`uname -a`

function log() {
   message="[CORDYS CRM Log]: $1 "
   echo -e "${message}" 2>&1 | tee -a ${__current_dir}/install.log
}
set -a
__local_ip=$(hostname -I|cut -d" " -f 1)
source ${__current_dir}/install.conf

export INSTALL_TYPE='install'
if [ -f ~/.cordysrc ];then
  source ~/.cordysrc > /dev/null
  echo "存在已安装的 CORDYS CRM, 安装目录为 ${CORDYS_BASE}/cordys, 执行升级流程"
  INSTALL_TYPE='upgrade'
elif [ -f /usr/local/bin/crmctl ];then
  CORDYS_BASE=$(cat /usr/local/bin/crmctl | grep CORDYS_BASE= | awk -F= '{print $2}' 2>/dev/null)
  echo "存在已安装的 CORDYS CRM, 安装目录为 ${CORDYS_BASE}/cordys, 执行升级流程"
  INSTALL_TYPE='upgrade'
else
  CORDYS_BASE=$(cat ${__current_dir}/install.conf | grep CORDYS_BASE= | awk -F= '{print $2}' 2>/dev/null)
  echo "安装目录为 ${CORDYS_BASE}/cordys, 开始进行安装"
  INSTALL_TYPE='install'
fi
set +a

__current_version=$(cat ${CORDYS_BASE}/cordys/version 2>/dev/null || echo "")
__target_version=$(cat ${__current_dir}/cordys/version)
# 截取实际版本
current_version=${__current_version%-*}
current_version=${current_version:1}
current_version_arr=(`echo $current_version | tr '.' ' '`)

target_version=${__target_version%-*}
target_version=${target_version:1}
target_version_arr=(`echo $target_version | tr '.' ' '`)

current_version=$(printf '1%02d%02d%02d' ${current_version_arr[0]} ${current_version_arr[1]} ${current_version_arr[2]})
target_version=$(printf '1%02d%02d%02d' ${target_version_arr[0]} ${target_version_arr[1]} ${target_version_arr[2]})


if [[ ${current_version} > ${target_version} ]]; then
  echo -e "\e[31m不支持降级\e[0m"
  return 2
fi

log "拷贝安装文件到目标目录"

mkdir -p ${CORDYS_BASE}/cordys
cp -f ./cordys/version ${CORDYS_BASE}/cordys/version
cp -rv --suffix=.$(date +%Y%m%d-%H%M) ./cordys ${CORDYS_BASE}/

# 记录MeterSphere安装路径
echo "CORDYS_BASE=${CORDYS_BASE}" > ~/.cordysrc
# 安装 crmctl 命令
cp crmctl /usr/local/bin && chmod +x /usr/local/bin/crmctl
ln -s /usr/local/bin/crmctl /usr/bin/crmctl 2>/dev/null

log "======================= 开始安装 ======================="
#Install docker & docker-compose
##Install Latest Stable Docker Release
if which docker >/dev/null; then
   log "检测到 Docker 已安装，跳过安装步骤"
   log "启动 Docker "
   service docker start 2>&1 | tee -a ${__current_dir}/install.log
else
   if [[ -d docker ]]; then
      log "... 离线安装 docker"
      chmod +x docker/bin/*
      cp docker/bin/* /usr/bin/
      cp docker/service/docker.service /etc/systemd/system/
      chmod 754 /etc/systemd/system/docker.service
      log "... 启动 docker"
      service docker start 2>&1 | tee -a ${__current_dir}/install.log

   else
      log "... 在线安装 docker"
      curl -fsSL https://resource.fit2cloud.com/get-docker-linux.sh -o get-docker.sh 2>&1 | tee -a ${__current_dir}/install.log
      sudo sh get-docker.sh 2>&1 | tee -a ${__current_dir}/install.log
      log "... 启动 docker"
      service docker start 2>&1 | tee -a ${__current_dir}/install.log
   fi

fi

# 检查docker服务是否正常运行
docker ps 1>/dev/null 2>/dev/null
if [ $? != 0 ];then
   log "Docker 未正常启动，请先安装并启动 Docker 服务后再次执行本脚本"
   exit
fi

##Install Latest Stable Docker Compose Release
if which docker-compose >/dev/null; then
   log "检测到 Docker Compose 已安装，跳过安装步骤"
else
   if [[ -d docker ]]; then
      log "... 离线安装 docker-compose"
      cp docker/bin/docker-compose /usr/bin/
      chmod +x /usr/bin/docker-compose
   else
      log "... 在线安装 docker-compose"
      curl -L https://resource.fit2cloud.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s | tr A-Z a-z)-`uname -m` -o /usr/local/bin/docker-compose 2>&1 | tee -a ${__current_dir}/install.log
      chmod +x /usr/local/bin/docker-compose
      ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
   fi
fi
# 检查docker-compose是否正常
docker-compose version 1>/dev/null 2>/dev/null
if [ $? != 0 ];then
   log "docker-compose 未正常安装，请先安装 docker-compose 后再次执行本脚本"
   exit
fi

# 将配置信息存储到安装目录的环境变量配置文件中
echo '' >> ${CORDYS_BASE}/cordys/.env
cp -f ${__current_dir}/install.conf ${CORDYS_BASE}/cordys/install.conf.example

# 通过加载环境变量的方式保留已修改的配置项，仅添加新增的配置项
source ${__current_dir}/install.conf
source ~/.cordysrc >/dev/null 2>&1
__cordys_image_tag=${CORDYS_IMAGE_TAG}
source ${CORDYS_BASE}/cordys/.env

export CORDYS_IMAGE_TAG=${__cordys_image_tag}
env | grep CORDYS_ > ${CORDYS_BASE}/cordys/.env
ln -s ${CORDYS_BASE}/cordys/.env ${CORDYS_BASE}/cordys/install.conf 2>/dev/null
grep "127.0.0.1 $(hostname)" /etc/hosts >/dev/null || echo "127.0.0.1 $(hostname)" >> /etc/hosts

crmctl generate_compose_files

exec > >(tee -a ${__current_dir}/install.log) 2>&1
set -e
export COMPOSE_HTTP_TIMEOUT=180
cd ${__current_dir}
# 加载镜像
if [[ -d images ]]; then
   log "加载镜像"
   for i in $(ls images); do
      docker load -i images/$i
   done
else
   log "拉取镜像"
   crmctl pull
   curl -sfL https://resource.fit2cloud.com/installation-log.sh | sh -s cordys ${INSTALL_TYPE} ${CORDYS_IMAGE_TAG}
   cd -
fi

log "启动服务"
crmctl down -v
crmctl up -d --remove-orphans

crmctl status

echo -e "======================= 安装完成 =======================\n"

echo -e "请通过以下方式访问:\n URL: http://\$LOCAL_IP:${CORDYS_SERVER_PORT}\n 用户名: admin\n 初始密码: cordys"
echo -e "您可以使用命令 'crmctl status' 检查服务运行情况.\n"