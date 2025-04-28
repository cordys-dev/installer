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
        checkoutToSubdirectory('installer')
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
                    // 如果提供了branch参数，则设置BRANCH_NAME环境变量
                    if (params.branch != null) {
                        env.BRANCH_NAME = params.branch
                    }
                    // 处理release参数，移除-arm64后缀
                    if (params.release != null) {
                        env.RELEASE = params.release.replace("-arm64", "")
                    } else {
                        env.RELEASE = env.BRANCH_NAME
                    }

                    // 打印当前版本和分支信息
                    echo "RELEASE=${RELEASE}"
                    echo "BRANCH=${BRANCH_NAME}"
                }
            }
        }

        // 阶段2：触发 GitHub Actions 构建镜像
        stage('Trigger GitHub Actions') {
            steps {
                // 使用GitHub Token进行身份验证
                    withCredentials([string(credentialsId: 'ZY-GITHUB-TOKEN', variable: 'TOKEN')]) {
                        withEnv(["TOKEN=$TOKEN"]) {
                        script {
                            // 社区版API端点
                            def ceWorkflowApi = "https://api.github.com/repos/fit2-zhao/actions/actions/workflows/build-and-push.yml/dispatches"
                            def ceRepoApi = "https://api.github.com/repos/fit2-zhao/actions/actions/runs"

                            // 企业版API端点
                            def eeWorkflowApi = "https://api.github.com/repos/fit2-zhao/actions/actions/workflows/build-and-push-xpack.yml/dispatches"
                            def eeRepoApi = "https://api.github.com/repos/fit2-zhao/actions/actions/runs"

                            // 触发社区版构建工作流
                            echo "开始触发社区版构建工作流..."
                            def ceResponse = sh(script: """
                                               curl -X POST -H "Authorization: Bearer $TOKEN" \\
                                                    -H "Accept: application/vnd.github.v3+json" \\
                                                    ${ceWorkflowApi} \\
                                                    -d '{ "ref":"main", "inputs":{"dockerImageTag":"${RELEASE}", "architecture":"linux/amd64", "registry":"fit2cloud-registry"}}'
                                             """, returnStatus: true)


                            if (ceResponse != 0) {
                                error "社区版镜像构建工作流触发失败"
                            }

                            echo "社区版镜像构建工作流触发成功，开始监控执行状态..."

                            // 检查社区版工作流状态
                            def ceBuildSuccess = false
                            timeout(time: 30, unit: 'MINUTES') {
                                waitUntil {
                                    sleep(time: 10, unit: 'SECONDS')
                                    def statusJson = sh(script: '''
                                        curl -s -H "Authorization: Bearer $TOKEN" \
                                        "''' + ceRepoApi + '''?event=workflow_dispatch&per_page=1"
                                    ''', returnStdout: true).trim()

                                    def status = sh(script: "echo '$statusJson' | grep -oP '\"status\": \"\\K[^\"]+' || echo 'unknown'", returnStdout: true).trim()
                                    def conclusion = sh(script: "echo '$statusJson' | grep -oP '\"conclusion\": \"\\K[^\"]+' || echo 'unknown'", returnStdout: true).trim()

                                    echo "社区版工作流当前状态: ${status}"

                                    if (status == "completed") {
                                        if (conclusion == "success") {
                                            echo "社区版构建工作流执行成功!"
                                            ceBuildSuccess = true
                                            return true
                                        } else {
                                            error "社区版构建工作流执行失败"
                                        }
                                    }

                                    return false
                                }
                            }

                            // 确认社区版构建成功后，触发企业版构建工作流
                            if (ceBuildSuccess) {
                                echo "开始触发企业版构建工作流..."
                                def eeResponse = sh(script: """
                                                   curl -X POST -H "Authorization: Bearer $TOKEN" \\
                                                        -H "Accept: application/vnd.github.v3+json" \\
                                                        ${eeWorkflowApi} \\
                                                        -d '{ "ref":"main", "inputs":{"dockerImageTag":"${RELEASE}", "architecture":"linux/amd64"}}'
                                                 """, returnStatus: true)
                                if (eeResponse != 0) {
                                    error "企业版镜像构建工作流触发失败"
                                }

                                echo "企业版镜像构建工作流触发成功，开始监控执行状态..."

                                // 检查企业版工作流状态
                                timeout(time: 30, unit: 'MINUTES') {
                                    waitUntil {
                                        sleep(time: 10, unit: 'SECONDS')
                                        def statusJson = sh(script: '''
                                            curl -s -H "Authorization: Bearer $TOKEN" \
                                            "''' + eeRepoApi + '''?event=workflow_dispatch&per_page=1"
                                        ''', returnStdout: true).trim()

                                        def status = sh(script: "echo '$statusJson' | grep -oP '\"status\": \"\\K[^\"]+' || echo 'unknown'", returnStdout: true).trim()
                                        def conclusion = sh(script: "echo '$statusJson' | grep -oP '\"conclusion\": \"\\K[^\"]+' || echo 'unknown'", returnStdout: true).trim()

                                        echo "企业版工作流当前状态: ${status}"

                                        if (status == "completed") {
                                            if (conclusion == "success") {
                                                echo "企业版构建工作流执行成功!"
                                                return true
                                            } else {
                                                error "企业版构建工作流执行失败"
                                            }
                                        }

                                        return false
                                    }
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
                    sh script: '''
                        # 清理旧的安装包
                        rm -rf cordys-*.tar.gz

                        # 修改安装配置文件中的镜像标签和前缀
                        sed -i -e "s#CORDYS_IMAGE_TAG=.*#CORDYS_IMAGE_TAG=${RELEASE}#g" install.conf
                        sed -i -e "s#CORDYS_IMAGE_PREFIX=.*#CORDYS_IMAGE_PREFIX=${IMAGE_PREFIX}#g" install.conf

                        # 将版本号写入version文件
                        echo ${RELEASE} > ./cordys/version
                    '''
                }
            }
        }

        // 阶段4：打包在线安装包
        stage('Package Online-install') {
            steps {
                dir('installer') {
                   sh script: """
                       touch cordys-crm-ce-online-installer-${RELEASE}.tar.gz
                       tar --transform "s/^\\./cordys-crm-ce-online-installer-${RELEASE}/" \\
                           --exclude cordys-crm-ce-online-installer-${RELEASE}.tar.gz \\
                           --exclude cordys-crm-ce-offline-installer-${RELEASE}.tar.gz \\
                           --exclude cordys-crm-ce-release-${RELEASE}.tar.gz \\
                           --exclude .git \\
                           --exclude images \\
                           --exclude community \\
                           --exclude enterprise \\
                           --exclude docker \\
                           -czvf cordys-crm-ce-online-installer-${RELEASE}.tar.gz .
                   """
                }
            }
        }
        // 阶段5：发布到GitHub
        stage('Release and Upload Asset') {
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
                                            "body": "${BRANCH_NAME}",
                                            "draft": false,
                                            "prerelease": true
                                        }' \
                                        https://api.github.com/repos/cordys-dev/cordys-crm/releases
                                """,
                                returnStdout: true
                            ).trim()

                            // 提取 upload_url
                            def uploadUrl = createReleaseResponse.split('"upload_url":')[1].split('"')[1].replaceAll("\\{\\?name,label\\}", "")
                            echo "Upload URL: ${uploadUrl}"

                            // 上传附件
                            sh """
                                curl -sSL -X POST \
                                    -H "Authorization: Bearer ${TOKEN}" \
                                    -H "Content-Type: application/octet-stream" \
                                    --data-binary @cordys-crm-ce-online-installer-${RELEASE}.tar.gz \
                                    "${uploadUrl}?name=cordys-crm-ce-online-installer-${RELEASE}.tar.gz"
                            """

                            // 上传到 uploadToOss
                            /* sh """
                                ossutil -c /opt/jenkins-home/cordys/config cp -f cordys-ce-online-installer-${RELEASE}.tar.gz oss://resource-fit2cloud-com/cordys/cordys/releases/download/${RELEASE}/ --update

                            """ */
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
                        // 定义需要拉取的Docker镜像列表
                        def images = ['mysql:8.0.41',
                                    'redis:7.2.7-alpine',
                                    "cordys-crm-ce:${RELEASE}",
                                    "cordys-crm-ee:${RELEASE}"
                                    ]
                        // 拉取所有需要的Docker镜像
                        for (image in images) {
                            waitUntil {
                                def r = sh script: "docker pull ${IMAGE_PREFIX}/${image}", returnStatus: true
                                r == 0;
                            }
                        }
                    }
                    sh script: """
                        # 保存社区版所需镜像
                        rm -rf images && mkdir images && cd images
                        docker save ${IMAGE_PREFIX}/cordys-crm-ce:${RELEASE} \\
                        ${IMAGE_PREFIX}/mysql:8.0.41 \\
                        ${IMAGE_PREFIX}/redis:7.2.7-alpine > cordys-crm.tar
                        cd ..

                        # 保存企业版所需镜像
                        rm -rf enterprise && mkdir enterprise && cd enterprise
                        docker save ${IMAGE_PREFIX}/cordys-crm-ee:${RELEASE} \\
                        ${IMAGE_PREFIX}/mysql:8.0.41 \\
                        ${IMAGE_PREFIX}/redis:7.2.7-alpine > cordys-crm.tar
                        cd ..
                    """
                    script {
                        // 处理架构信息（x86_64或arm64）
                        RELEASE = ""
                        ARCH = "x86_64"
                        if (env.TAG_NAME != null) {
                            RELEASE = env.TAG_NAME
                            if (RELEASE.endsWith("-arm64")) {
                                ARCH = "aarch64"
                            }
                        } else {
                            RELEASE = env.BRANCH_NAME
                        }
                        env.RELEASE = "${RELEASE}"
                        env.ARCH = "${ARCH}"
                        echo "RELEASE=${RELEASE}"
                        echo "ARCH=${ARCH}"
                    }
                    sh script: """
                        # 准备docker相关文件
                        rm -rf docker *//*
                        rm -rf docker

                        # 下载对应架构的docker和docker-compose
                        wget https://resource.fit2cloud.com/docker/download/${ARCH}/docker-25.0.2.tgz
                        wget https://resource.fit2cloud.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-${ARCH} && mv docker-compose-linux-${ARCH} docker-compose && chmod +x docker-compose
                        tar -zxvf docker-25.0.2.tgz
                        rm -rf docker-25.0.2.tgz
                        mv docker bin && mkdir docker && mv bin docker/
                        mv docker-compose docker/bin
                        mkdir docker/service && mv docker.service docker/service/

                        # 打包社区版离线安装包
                        touch cordys-crm-ce-offline-installer-${RELEASE}.tar.gz
                        tar --transform 's/^\\./cordys-crm-ce-offline-installer-${RELEASE}/' \\
                            --exclude cordys-crm-ce-online-installer-${RELEASE}.tar.gz \\
                            --exclude cordys-crm-ce-offline-installer-${RELEASE}.tar.gz \\
                            --exclude cordys-crm-ce-release-${RELEASE}.tar.gz \\
                            --exclude .git \\
                            --exclude enterprise \\
                            -czvf cordys-crm-ce-offline-installer-${RELEASE}.tar.gz .

                        # 生成MD5校验文件
                        md5sum -b cordys-crm-ce-offline-installer-${RELEASE}.tar.gz | awk '{print \$1}' > cordys-crm-ce-offline-installer-${RELEASE}.tar.gz.md5
                        rm -rf images

                        # 准备企业版镜像
                        mv enterprise images
                        # 修改配置文件中的-ce为-ee
                        sed -i -e 's#-ce#-ee#g' cordys/docker-compose-cordys.yml

                        # 添加企业版特有配置
                        echo '# 企业版配置' >> install.conf
                        echo 'CORDYS_ENTERPRISE_ENABLE=true' >> install.conf

                        # 清理临时文件
                        rm -rf cordys *//*.yml-e

                        # 打包企业版离线安装包
                        touch cordys-crm-ee-offline-installer-${RELEASE}.tar.gz
                        tar --transform 's/^\\./cordys-crm-ee-offline-installer-${RELEASE}/' \\
                            --exclude cordys-crm-ee-offline-installer-${RELEASE}.tar.gz \\
                            --exclude cordys-crm-ce-online-installer-${RELEASE}.tar.gz \\
                            --exclude cordys-crm-ce-offline-installer-${RELEASE}.tar.gz \\
                            --exclude cordys-crm-ce-offline-installer-${RELEASE}.tar.gz.md5 \\
                            --exclude .git \\
                            -czvf cordys-crm-ee-offline-installer-${RELEASE}.tar.gz .

                        # 生成企业版MD5校验文件
                        md5sum -b cordys-crm-ee-offline-installer-${RELEASE}.tar.gz | awk '{print \$1}' > cordys-crm-ee-offline-installer-${RELEASE}.tar.gz.md5
                        rm -rf images
                    """
                }
            }
        }

        // 阶段7：上传离线安装包到OSS
        stage('Upload') {
            when { tag pattern: "^v.*", comparator: "REGEXP" }
            steps {
                dir('installer') {
                    echo "UPLOADING"
                    // 使用OSS凭据上传文件
                    withCredentials([usernamePassword(credentialsId: 'OSSKEY', passwordVariable: 'SK', usernameVariable: 'AK')]) {
                        // 上传社区版离线安装包和MD5文件
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys/release/cordys-crm-ce-offline-installer-${RELEASE}.tar.gz ./cordys-crm-ce-offline-installer-${RELEASE}.tar.gz")
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys/release/cordys-crm-ce-offline-installer-${RELEASE}.tar.gz.md5 ./cordys-crm-ce-offline-installer-${RELEASE}.tar.gz.md5")

                        // 上传企业版离线安装包和MD5文件
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys/release/cordys-crm-ee-offline-installer-${RELEASE}.tar.gz ./cordys-crm-ee-offline-installer-${RELEASE}.tar.gz")
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys/release/cordys-crm-ee-offline-installer-${RELEASE}.tar.gz.md5 ./cordys-crm-ee-offline-installer-${RELEASE}.tar.gz.md5")
                    }
                }
            }
        }
    }

    // 后置处理：发送通知
    post('Notification') {
        always {
            // 使用企业微信webhook发送构建结果通知
            withCredentials([string(credentialsId: 'wechat-bot-webhook', variable: 'WEBHOOK')]) {
                qyWechatNotification failNotify: true, mentionedId: '', mentionedMobile: '', webhookUrl: "$WEBHOOK"
            }
        }
    }
}