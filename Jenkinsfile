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
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-ee-offline-installer-${RELEASE}-${ARCH}.tar.gz ./cordys-crm-ee-offline-installer-${RELEASE}-${ARCH}.tar.gz")
                        sh("java -jar /opt/uploadToOss.jar $AK $SK fit2cloud2-offline-installer cordys-crm/release/cordys-crm-ee-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5 ./cordys-crm-ee-offline-installer-${RELEASE}-${ARCH}.tar.gz.md5")
                    }
                }
            }
        }
    }
}
