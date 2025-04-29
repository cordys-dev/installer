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
                }
            }
        }

        // 阶段2：触发 GitHub Actions 构建镜像
        stage('Trigger GitHub Actions') {
            when {
                expression {
                    return env.ARCH ==~ /^x86.*/
                }
            }
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
                                                    -d '{ "ref":"main", "inputs":{"dockerImageTag":"${RELEASE}", "architecture":"linux/amd64,linux/arm64", "registry":"fit2cloud-registry"}}'
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
                                                        -d '{ "ref":"main", "inputs":{"dockerImageTag":"${RELEASE}", "architecture":"linux/amd64,linux/arm64"}}'
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
                    sh script: """
                        # 清理当前工作空间
                        shopt -s extglob
                        rm -rf !(conf)
                        shopt -u extglob

                        # 修改安装配置文件中的镜像标签和前缀
                        sed -i -e "s#CORDYS_IMAGE_TAG=.*#CORDYS_IMAGE_TAG=${RELEASE}#g" ./conf/install.conf
                        sed -i -e "s#CORDYS_IMAGE_PREFIX=.*#CORDYS_IMAGE_PREFIX=${IMAGE_PREFIX}#g" ./conf/install.conf

                        # 将版本号写入version文件
                        echo ${RELEASE} > ./conf/cordys/version
                    """
                }
            }
        }

        // 阶段4：打包在线安装包
        stage('Package Online-install') {
            when {
                expression {
                    return env.ARCH ==~ /^x86.*/
                }
            }
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
                    return env.ARCH ==~ /^x86.*/
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
                        def images = [
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

                        # 保存社区版所需镜像
                        rm -rf images && mkdir images && cd images
                        docker save ${IMAGE_PREFIX}/cordys-crm-ce:${RELEASE} > cordys-crm.tar
                        cd ..

                        # 打包社区版离线安装包
                        tar --transform "s|^|cordys-crm-ce-online-installer-${RELEASE}/|" \\
                            -czvf cordys-crm-ce-online-installer-${RELEASE}.tar.gz \\
                            docker images -C conf .

                        # 生成MD5校验文件
                        md5sum -b cordys-crm-ce-offline-installer-${RELEASE}.tar.gz | awk '{print \$1}' > cordys-crm-ce-offline-installer-${RELEASE}.tar.gz.md5

                       # 准备企业版镜像
                       rm -rf images && mkdir images && cd images
                       docker save ${IMAGE_PREFIX}/cordys-crm-ee:${RELEASE} > cordys-crm.tar
                       cd ..

                        # 添加企业版特有配置
                        echo '# 企业版配置' >> ./conf/install.conf
                        echo 'CORDYS_ENTERPRISE_ENABLE=true' >> ./conf/install.conf

                        # 打包企业版离线安装包
                        tar --transform "s|^|cordys-crm-ee-online-installer-${RELEASE}/|" \\
                          -czvf cordys-crm-ee-online-installer-${RELEASE}.tar.gz \\
                          docker images -C conf .

                        # 生成企业版MD5校验文件
                        md5sum -b cordys-crm-ee-offline-installer-${RELEASE}.tar.gz | awk '{print \$1}' > cordys-crm-ee-offline-installer-${RELEASE}.tar.gz.md5
                        rm -rf images conf
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
//     post('Notification') {
//         always {
//             // 使用企业微信webhook发送构建结果通知
//             withCredentials([string(credentialsId: 'wechat-bot-webhook', variable: 'WEBHOOK')]) {
//                 qyWechatNotification failNotify: true, mentionedId: '', mentionedMobile: '', webhookUrl: "$WEBHOOK"
//             }
//         }
//     }
}