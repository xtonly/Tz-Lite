#!/bin/bash

# ================= 配置区域 =================
BASE_DIR="/opt/lite-monitor"
DATA_DIR="${BASE_DIR}/data"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

IMAGE_NAME="ghcr.io/nuomiiiii/lite:latest" 
CONTAINER_PORT="12777"     # 宿主机映射端口
INTERNAL_PORT="27777"      # 容器内部实际监听端口 (根据日志已修正)
CONTAINER_DATA_DIR="/data" 
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
services:
  lite-monitor:
    image: ${IMAGE_NAME}
    container_name: lite-monitor
    restart: always
    ports:
      - "${CONTAINER_PORT}:${INTERNAL_PORT}"
    volumes:
      - ./data:${CONTAINER_DATA_DIR}
    environment:
      - TZ=Asia/Shanghai
    network_mode: bridge
EOF
    echo "配置文件已生成: $COMPOSE_FILE"
}

# 自动配置防火墙放行端口
configure_firewall() {
    echo "正在自动配置防火墙规则..."
    if command -v ufw &> /dev/null; then
        ufw allow ${CONTAINER_PORT}/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
        echo "已通过 UFW 放行 ${CONTAINER_PORT} 端口。"
    elif command -v iptables &> /dev/null; then
        # 检查是否已存在规则，防止重复添加
        if ! iptables -C INPUT -p tcp --dport ${CONTAINER_PORT} -j ACCEPT &> /dev/null; then
            iptables -I INPUT -p tcp --dport ${CONTAINER_PORT} -j ACCEPT
            echo "已通过 iptables 放行 ${CONTAINER_PORT} 端口。"
        else
            echo "iptables 已存在该端口的放行规则，跳过添加。"
        fi
    else
        echo "未检测到 ufw 或 iptables，跳过系统防火墙配置。"
    fi
}

# 启动服务并显示访问地址
start_service() {
    echo "正在启动 Lite 监控服务端..."
    cd "$BASE_DIR" || exit
    
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    # 获取公网 IP
    SERVER_IP=$(curl -s --connect-timeout 3 ifconfig.me || echo "<你的服务器IP>")
    
    echo ""
    echo "========================================================"
    echo " 🎉 Lite 监控服务端已成功启动！"
    echo " 🌐 Web 端访问地址: http://${SERVER_IP}:${CONTAINER_PORT}"
    echo " 🛡️  系统防火墙规则已自动放行。"
    echo " ⚠️  注意: 如果使用的是云服务器，请确保网页端安全组也已放行 ${CONTAINER_PORT} (TCP)。"
    echo "========================================================"
    echo ""
}

# 升级服务（无损数据）
upgrade_service() {
    echo "开始升级 Lite 监控服务端，现有数据将自动保留..."
    if [ ! -d "$BASE_DIR" ] || [ ! -f "$COMPOSE_FILE" ]; then
        echo "未找到安装目录或配置文件，请先执行安装！"
        exit 1
    fi
    
    cd "$BASE_DIR" || exit
    
    if docker compose version &> /dev/null; then
        docker compose pull
        docker compose down
        docker compose up -d
    else
        docker-compose pull
        docker-compose down
        docker-compose up -d
    fi
    
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
            configure_firewall
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

# 执行旧容器清理（确保重新运行 1 安装时端口能正确映射）
if [ "$(docker ps -aq -f name=lite-monitor)" ]; then
    echo "检测到旧的 lite-monitor 容器，准备执行重新部署..."
    docker rm -f lite-monitor >/dev/null 2>&1
fi

menu
