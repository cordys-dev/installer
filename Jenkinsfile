// 定义整个流水线
pipeline {
    // 指定运行节点
    agent {
        node {
            // 如果参数label为空则默认使用"cordys"节点，否则使用参数指定的节点
            label params.label == "" ? "cordys" : params.label
        }
    }

    // 全局选项配置
    options {
        // 将代码检出到installer子目录
        checkoutToSubdirectory('installer/conf')
    }

    // 环境变量设置
    environment {
        // Docker镜像前缀
        IMAGE_PREFIX = "registry.fit2cloud.com/cordys"
    }
    
    // 流水线阶段定义
    stages {
        // 阶段1：准备工作
        stage('Preparation') {
            steps {
                script {
                    // 打印当前版本和分支信息
                    echo "RELEASE=${RELEASE}"
                    echo "BRANCH=${BRANCH}"
                    echo "ARCH=${ARCH}"
                    echo "ARCHITECTURE=${ARCHITECTURE}"
                    echo "OVERRIDE=${OVERRIDE}"
                }
            }
        }

        // 阶段2：触发 GitHub Actions 构建镜像
        stage('Trigger GitHub Actions') {
            steps {
                withCredentials([string(credentialsId: 'ZY-GITHUB-TOKEN', variable: 'TOKEN')]) {
                    script {
                        def payload = groovy.json.JsonOutput.toJson([
                            ref: 'main',
                            inputs: [dockerImageTag: env.RELEASE, architecture: env.ARCHITECTURE,
                                     csBranch: env.BRANCH, isOverride: env.OVERRIDE],
                            return_run_details: true
                        ])
                        def dispatchResponse
                        withEnv(["DISPATCH_PAYLOAD=${payload}"]) {
                            dispatchResponse = sh(script: '''
                                curl --fail --silent --show-error --max-time 30 -X POST \\
                                    -H "Authorization: Bearer $TOKEN" \\
                                    -H "Accept: application/vnd.github+json" \\
                                    -H "X-GitHub-Api-Version: 2026-03-10" \\
                                    -d "$DISPATCH_PAYLOAD" \\
                                    https://api.github.com/repos/fit2-zhao/actions/actions/workflows/build-and-push-x.yml/dispatches
                            ''', returnStdout: true).trim()
                        }

                        def runIdMatch = dispatchResponse =~ /"workflow_run_id"\s*:\s*([0-9]+)/
                        if (!runIdMatch.find()) {
                            error '触发响应没有工作流运行 ID，无法监控本次构建'
                        }
                        def runId = runIdMatch.group(1)
                        runIdMatch = null
                        echo "已触发工作流: https://github.com/fit2-zhao/actions/actions/runs/${runId}"

                        withEnv(["RUN_ID=${runId}"]) {
                            timeout(time: 80, unit: 'MINUTES') {
                                waitUntil {
                                    sleep(time: 10, unit: 'SECONDS')
                                    def statusJson = sh(script: '''
                                        curl --fail --silent --show-error --max-time 30 \\
                                            -H "Authorization: Bearer $TOKEN" \\
                                            -H "Accept: application/vnd.github+json" \\
                                            -H "X-GitHub-Api-Version: 2026-03-10" \\
                                            "https://api.github.com/repos/fit2-zhao/actions/actions/runs/$RUN_ID"
                                    ''', returnStdout: true).trim()
                                    def statusMatch = statusJson =~ /"status"\s*:\s*"([^"]+)"/
                                    if (!statusMatch.find()) {
                                        error '工作流响应没有状态'
                                    }
                                    def status = statusMatch.group(1)
                                    statusMatch = null
                                    echo "工作流 ${runId} 当前状态: ${status}"

                                    if (status == 'completed') {
                                        def conclusionMatch = statusJson =~ /"conclusion"\s*:\s*"([^"]+)"/
                                        def conclusion = conclusionMatch.find() ? conclusionMatch.group(1) : 'unknown'
                                        conclusionMatch = null
                                        if (conclusion != 'success') {
                                            error "构建工作流执行失败: ${conclusion}"
                                        }
                                        echo '构建工作流执行成功!'
                                        return true
                                    }
                                    return false
                                }
                            }
                        }
                    }
                }
            }
        }

        // 阶段3：修改安装配置文件
        stage('Modify install conf') {
            steps {
                dir('installer') {
                    sh script: """
                        # 清理当前工作空间
                        shopt -s extglob
                        rm -rf !(conf)
                        shopt -u extglob

                        # 修改安装配置文件中的镜像标签和前缀
                        sed -i -e \"s#CORDYS_IMAGE_TAG=.*#CORDYS_IMAGE_TAG=${RELEASE}#g\" ./conf/install.conf
                        sed -i -e \"s#CORDYS_IMAGE_PREFIX=.*#CORDYS_IMAGE_PREFIX=${IMAGE_PREFIX}#g\" ./conf/install.conf

                        # 将版本号写入version文件
                        echo ${RELEASE} > ./conf/cordys/version
                    """
                }
            }
        }

        // 阶段4：打包在线安装包
        stage('Package Online-install') {
            steps {
                dir('installer') {
                   sh script: """
                            tar --transform "s|^|cordys-crm-ce-online-installer-${RELEASE}/|" \\
                                -czvf cordys-crm-ce-online-installer-${RELEASE}.tar.gz -C conf .
                   """
                }
            }
        }
        // 阶段5：发布到GitHub
        stage('Release and Upload Asset') {
            when {
                expression {
                    return env.ARCH ==~ /^x86.*/ && env.OVERRIDE == "false"
                }
            }
            steps {
                withCredentials([string(credentialsId: 'ZY-GITHUB-TOKEN', variable: 'TOKEN')]) {
                    dir('installer') {
                        script {
                            // 创建 release
                            def createReleaseResponse = sh(
                                script: """
                                    curl -sSL -X POST \
                                        -H "Accept: application/vnd.github+json" \
                                        -H "Authorization: Bearer ${TOKEN}" \
                                        -H "Content-Type: application/json" \
                                        -d '{
                                            "tag_name": "${RELEASE}",
                                            "name": "${RELEASE}",
                                            "body": "${BRANCH}",
                                            "draft": false,
                                            "prerelease": true
                                        }' \
                                        https://api.github.com/repos/1Panel-dev/CordysCRM/releases
                                """,
                                returnStdout: true
                            ).trim()
                        }
                    }
                }
            }
        }
        // 阶段6：打包离线安装包
        stage('Package Offline-install') {
            steps {
                dir('installer') {
                    script {
                    withCredentials([usernamePassword(credentialsId: 'harbor-developer',
                                                                     usernameVariable: 'USERNAME',
                                                                     passwordVariable: 'PASSWORD')]) {
                                        def registryServer = "registry.fit2cloud.com"

                                        sh "docker login -u ${USERNAME} -p ${PASSWORD} ${registryServer}"
                                    }
                        // 定义需要拉取的Docker镜像列表
                        def images = ["cordys-crm:${RELEASE}"]
                        // 拉取所有需要的Docker镜像
                        for (image in images) {
                            waitUntil {
                                def r = sh script: "docker pull ${IMAGE_PREFIX}/${image}", returnStatus: true
                                r == 0;
                            }
                        }
                    }
                    sh script: """
                        # 准备docker相关文件

                        echo "RELEASE=${RELEASE}"
                        echo "ARCH=${ARCH}"

                        # 下载对应架构的docker和docker-compose
                        wget https://resource.fit2cloud.com/docker/download/${ARCH}/docker-25.0.2.tgz
                        wget https://resource.fit2cloud.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-${ARCH} && mv docker-compose-linux-${ARCH} docker-compose && chmod +x docker-compose
                        tar -zxvf docker-25.0.2.tgz
                        rm -rf docker-25.0.2.tgz
                        mv docker bin && mkdir docker && mv bin docker/
                        mv docker-compose docker/bin
                        mkdir docker/service && mv ./conf/docker.service docker/service/

                       # 准备企业版镜像
                       rm -rf images && mkdir images && cd images
                       docker save ${IMAGE_PREFIX}/cordys-crm:${RELEASE} > cordys-crm.tar
                       cd ..

                        # 添加企业版特有配置
                        echo >> ./conf/install.conf
                        echo '# 企业版配置' >> ./conf/install.conf
                        echo 'CORDYS_ENTERPRISE_ENABLE=true' >> ./conf/install.conf
                        sed -i -e \"s#CORDYS_IMAGE_NAME=.*#CORDYS_IMAGE_NAME=cordys-crm#g\" ./conf/install.conf

                        # 打包企业版离线安装包
                        tar --transform "s|^|cordys-crm-offline-installer-${RELEASE}-${ARCH}/|" \\
                          -czvf cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz \\
                          docker images -C conf .


                        # 生成企业版MD5校验文件
                        md5sum -b cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz | awk '{print \$1}' > cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5
                        rm -rf images conf
                    """
                }
            }
        }

        // 阶段7：上传离线安装包到OSS
        stage('Upload for AMD64') {
             when {
                expression {
                    return env.ARCH ==~ /^x86.*/
                }
            }
            steps {
                dir('installer') {
                    echo "UPLOADING"
                    // 使用OSS凭据上传文件
                    withCredentials([usernamePassword(credentialsId: 'OSSKEY', passwordVariable: 'SK', usernameVariable: 'AK')]) {
                        // 上传企业版离线安装包和MD5文件
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz ./cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz")
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5 ./cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5")
                    }
                }
            }
        }
      // 阶段8：上传离线安装包到OSS
        stage('Upload for ARM') {
            when {
                  expression {
                     return env.ARCH == "aarch64"
                  }
            }
            steps {
                dir('installer') {
                    echo "UPLOADING"
                    // 使用OSS凭据上传文件
                    withCredentials([usernamePassword(credentialsId: 'OSSKEY', passwordVariable: 'SK', usernameVariable: 'AK')]) {
                        // 上传企业版离线安装包和MD5文件
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz ./cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz")
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5 ./cordys-crm-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5")
                    }
                }
            }
        }
    }
}
