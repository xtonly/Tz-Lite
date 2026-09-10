#!/bin/bash

# ================= 配置区域 =================
BASE_DIR="/opt/lite-monitor"
DATA_DIR="${BASE_DIR}/data"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

# 根据实际镜像托管地址修改。如果是 GitHub 镜像库，可能是 ghcr.io/nuomiiiii/lite:latest
IMAGE_NAME="nuomiiiii/lite:latest" 
CONTAINER_PORT="8080"      # 宿主机映射端口
CONTAINER_DATA_DIR="/data" # 容器内部的数据存储路径（请根据 Lite 的实际文档调整此处）
# ============================================

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

# 安装 Docker 依赖
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "未检测到 Docker，正在自动安装..."
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl enable docker
        systemctl start docker
    else
        echo "Docker 已安装，跳过此步骤。"
    fi

    # 兼容老版本 docker-compose 检查
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo "正在安装 Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# 部署环境并生成 Compose 文件
setup_env() {
    echo "初始化环境与目录..."
    mkdir -p "$DATA_DIR"
    
    cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  lite-monitor:
    image: ${IMAGE_NAME}
    container_name: lite-monitor
    restart: always
    ports:
      - "${CONTAINER_PORT}:8080"
    volumes:
      # 核心：将宿主机目录挂载到容器内，保证更新容器时数据不丢失
      - ./data:${CONTAINER_DATA_DIR}
    environment:
      - TZ=Asia/Shanghai
    network_mode: bridge
EOF
    echo "配置文件已生成: $COMPOSE_FILE"
}

# 启动服务
start_service() {
    echo "正在启动 Lite 监控服务端..."
    cd "$BASE_DIR" || exit
    
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    echo "Lite 监控服务端已启动！"
}

# 升级服务（无损数据）
upgrade_service() {
    echo "开始升级 Lite 监控服务端，现有数据将自动保留..."
    if [ ! -d "$BASE_DIR" ] || [ ! -f "$COMPOSE_FILE" ]; then
        echo "未找到安装目录或配置文件，请先执行安装！"
        exit 1
    fi
    
    cd "$BASE_DIR" || exit
    
    # 核心升级逻辑：拉取新镜像 -> 销毁旧容器 -> 基于新镜像和旧挂载卷启动新容器
    if docker compose version &> /dev/null; then
        docker compose pull
        docker compose down
        docker compose up -d
    else
        docker-compose pull
        docker-compose down
        docker-compose up -d
    fi
    
    # 清理被替换下来的悬空(dangling)镜像，释放磁盘空间
    docker image prune -f
    echo "升级完成！数据已保留，服务正在运行。"
}

# 卸载服务
uninstall_service() {
    echo "警告：这将停止服务并删除容器。"
    read -p "是否要彻底删除挂载的持久化数据？(不可恢复) [y/N]: " del_data
    
    cd "$BASE_DIR" || exit
    if docker compose version &> /dev/null; then
        docker compose down
    else
        docker-compose down
    fi
    
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        cd /opt
        rm -rf "$BASE_DIR"
        echo "服务已卸载，所有数据和目录已彻底清理。"
    else
        echo "服务已卸载，数据依然保留在 $DATA_DIR"
    fi
}

# 交互式菜单
menu() {
    clear
    echo "================================================="
    echo " nuomiiiii/Lite 监控服务端 - Docker 一键管理脚本 "
    echo "================================================="
    echo " 1. 安装 Lite 监控服务端"
    echo " 2. 升级 Lite 监控服务端 (无损数据)"
    echo " 3. 卸载 Lite 监控服务端"
    echo " 0. 退出脚本"
    echo "================================================="
    read -p "请输入选项 [0-3]: " choice

    case $choice in
        1)
            install_docker
            setup_env
            start_service
            ;;
        2)
            upgrade_service
            ;;
        3)
            uninstall_service
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            sleep 2
            menu
            ;;
    esac
}

menu
