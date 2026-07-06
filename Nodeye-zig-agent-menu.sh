#!/bin/bash

SERVICE_NAME="Nodeye-agent"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="/opt/Nodeye"

function reload_daemon() {
    echo "重新加载 systemctl daemon..."
    systemctl daemon-reexec
    systemctl daemon-reload
}

function enable_service() {
    echo "设置 ${SERVICE_NAME} 开机自启..."
    systemctl enable "$SERVICE_NAME"
}

function disable_service() {
    echo "禁用 ${SERVICE_NAME} 开机自启..."
    systemctl disable "$SERVICE_NAME"
}

function start_service() {
    echo "启动 ${SERVICE_NAME}..."
    systemctl start "$SERVICE_NAME"
}

function stop_service() {
    echo "停止 ${SERVICE_NAME}..."
    systemctl stop "$SERVICE_NAME"
}

function restart_service() {
    echo "重启 ${SERVICE_NAME}..."
    systemctl restart "$SERVICE_NAME"
}

function status_service() {
    echo "查看 ${SERVICE_NAME} 状态..."
    systemctl status "$SERVICE_NAME"
}

function logs_service() {
    echo "查看 ${SERVICE_NAME} 实时日志..."
    journalctl -f -u "$SERVICE_NAME"
}

function update_agent() {
    echo "正在更新 ${SERVICE_NAME}..."
    
    # 检查是否已安装
    if [ ! -f "${INSTALL_DIR}/agent" ]; then
        echo -e "\033[1;31m错误：${SERVICE_NAME} 未安装，请先运行安装脚本\033[0m"
        return 1
    fi
    
    # 检查依赖
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "\033[1;31m错误：curl 未安装，无法下载更新\033[0m"
        return 1
    fi
    
    # 检测系统架构
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo -e "\033[1;31m错误：不支持的架构 $arch\033[0m"; return 1 ;;
    esac
    
    # 检测操作系统
    os_type=$(uname -s)
    case $os_type in
        Darwin) os_name="darwin" ;;
        Linux) os_name="linux" ;;
        *) echo -e "\033[1;31m错误：不支持的操作系统 $os_type\033[0m"; return 1 ;;
    esac
    
    echo "检测到系统：$os_name $arch"
    
    # 询问是否使用代理
    echo -n "是否使用 GitHub 代理？[y/N]: "
    read -r use_proxy
    github_proxy=""
    if [[ "$use_proxy" =~ ^[Yy]$ ]]; then
        echo -n "请输入代理地址 (例如: https://ghproxy.com): "
        read -r github_proxy
        github_proxy="${github_proxy%/}"  # 移除尾部斜杠
    fi
    
    # 询问更新版本
    echo -n "输入版本号（直接回车使用最新版本）: "
    read -r version_input
    
    # 构建下载 URL
    file_name="Nodeye-agent-${os_name}-${arch}"
    if [ -z "$version_input" ]; then
        download_path="latest/download"
        echo "准备下载最新版本..."
    else
        download_path="download/${version_input}"
        echo "准备下载版本：$version_input"
    fi
    
    if [ -n "$github_proxy" ]; then
        download_url="${github_proxy}/https://github.com/uyo8os/Nodeye-zig-agent/releases/${download_path}/${file_name}"
        echo "使用代理下载：$github_proxy"
    else
        download_url="https://github.com/uyo8os/Nodeye-zig-agent/releases/${download_path}/${file_name}"
        echo "直接下载"
    fi
    
    # 获取当前版本（如果可能）
    current_version=""
    if [ -x "${INSTALL_DIR}/agent" ]; then
        current_version=$(${INSTALL_DIR}/agent --version 2>/dev/null | head -1 || echo "未知版本")
        echo "当前版本：$current_version"
    fi
    
    # 备份当前文件
    backup_file="${INSTALL_DIR}/agent.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "${INSTALL_DIR}/agent" ]; then
        echo "备份当前文件到：$backup_file"
        cp "${INSTALL_DIR}/agent" "$backup_file"
    fi
    
    # 停止服务
    echo "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # 下载新版本
    temp_file="/tmp/Nodeye-agent-update-$$"
    echo "下载地址：$download_url"
    echo "正在下载..."
    if curl -L --progress-bar -o "$temp_file" "$download_url"; then
        # 验证文件是否有效（简单检查文件大小）
        if [ ! -s "$temp_file" ]; then
            echo -e "\033[1;31m下载失败：文件为空\033[0m"
            rm -f "$temp_file"
            if [ -f "$backup_file" ]; then
                echo "恢复备份文件..."
                cp "$backup_file" "${INSTALL_DIR}/agent"
            fi
            systemctl start "$SERVICE_NAME" 2>/dev/null || true
            return 1
        fi
        
        # 移动到目标位置
        mv "$temp_file" "${INSTALL_DIR}/agent"
        chmod +x "${INSTALL_DIR}/agent"
        chown Nodeye:Nodeye "${INSTALL_DIR}/agent" 2>/dev/null || true
        
        echo -e "\033[1;32m下载完成！\033[0m"
        
        # 获取新版本信息
        new_version=""
        if [ -x "${INSTALL_DIR}/agent" ]; then
            new_version=$(${INSTALL_DIR}/agent --version 2>/dev/null | head -1 || echo "未知版本")
            echo "新版本：$new_version"
        fi
        
        # 启动服务
        echo "启动服务..."
        systemctl start "$SERVICE_NAME"
        
        # 检查服务状态
        if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
            echo -e "\033[1;32m更新成功！服务已启动\033[0m"
            if [ -f "$backup_file" ]; then
                echo "备份文件保留在：$backup_file"
                echo "如果新版本工作正常，可以手动删除备份文件"
            fi
        else
            echo -e "\033[1;31m警告：服务启动失败，正在恢复备份...\033[0m"
            if [ -f "$backup_file" ]; then
                cp "$backup_file" "${INSTALL_DIR}/agent"
                systemctl start "$SERVICE_NAME"
                echo "已恢复到之前版本"
            fi
            return 1
        fi
    else
        echo -e "\033[1;31m下载失败\033[0m"
        rm -f "$temp_file"
        if [ -f "$backup_file" ]; then
            echo "恢复备份文件..."
            cp "$backup_file" "${INSTALL_DIR}/agent"
        fi
        systemctl start "$SERVICE_NAME" 2>/dev/null || true
        return 1
    fi
}

function cleanup_backups() {
    echo "清理备份文件..."
    backup_count=$(find "$INSTALL_DIR" -name "agent.backup.*" -type f 2>/dev/null | wc -l)
    
    if [ "$backup_count" -eq 0 ]; then
        echo "没有找到备份文件"
        return
    fi
    
    echo "找到 $backup_count 个备份文件："
    find "$INSTALL_DIR" -name "agent.backup.*" -type f -exec ls -lh {} \;
    
    echo -n "是否删除所有备份文件？[y/N]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        find "$INSTALL_DIR" -name "agent.backup.*" -type f -delete
        echo -e "\033[1;32m备份文件清理完成\033[0m"
    else
        echo "保留备份文件"
    fi
}

function show_version() {
    echo "查看 ${SERVICE_NAME} 版本信息..."
    if [ -x "${INSTALL_DIR}/agent" ]; then
        echo "当前版本："
        ${INSTALL_DIR}/agent --version 2>/dev/null || echo "无法获取版本信息"
    else
        echo -e "\033[1;31m${SERVICE_NAME} 未安装\033[0m"
    fi
}

function uninstall_agent() {
    echo "正在卸载 ${SERVICE_NAME}..."

    # 停止和禁用服务
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"

    # 删除 systemd 服务文件
    if [ -f "$SERVICE_PATH" ]; then
        rm -f "$SERVICE_PATH"
        echo "已删除服务文件：$SERVICE_PATH"
    fi

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        echo "删除目录：$INSTALL_DIR"
        sudo rm -rf "$INSTALL_DIR"
    else
        echo "目录 $INSTALL_DIR 不存在，无需删除。"
    fi

    # 重新加载 systemd
    systemctl daemon-reload
    echo "${SERVICE_NAME} 卸载完成。"
}

function get_service_status() {
    if [ ! -f "$SERVICE_PATH" ]; then
        echo -e "状态：\033[1;33m⚠️ 未安装\033[0m"
    else
        STATUS=$(systemctl is-active "$SERVICE_NAME")
        if [ "$STATUS" == "active" ]; then
            echo -e "状态：\033[1;32m✅ 运行中\033[0m"
        elif [ "$STATUS" == "inactive" ]; then
            echo -e "状态：\033[1;31m❌ 未启动\033[0m"
        else
            echo -e "状态：\033[1;31m❌ 状态异常：$STATUS\033[0m"
        fi
    fi
}

function show_menu() {
    echo "======== Nodeye Agent 管理菜单 ========"
    echo "1. 重新加载 systemctl daemon"
    echo "2. 设置开机自启"
    echo "3. 禁用开机自启"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 重启服务"
    echo "7. 查看服务状态"
    echo "8. 查看服务日志"
    echo "9. 更新 Nodeye Agent"
    echo "10. 查看版本信息"
    echo "11. 清理备份文件"
    echo "12. 卸载 Nodeye Agent"
    echo "0. 退出"
    echo "======================================="
    get_service_status
    echo -n "请输入选项编号: "
}

while true; do
    show_menu
    read -r choice
    case $choice in
        1) reload_daemon ;;
        2) enable_service ;;
        3) disable_service ;;
        4) start_service ;;
        5) stop_service ;;
        6) restart_service ;;
        7) status_service ;;
        8) logs_service ;;
        9) update_agent ;;
        10) show_version ;;
        11) cleanup_backups ;;
        12) uninstall_agent ;;
        0) echo "退出"; exit 0 ;;
        *) echo "无效的选项，请重新输入。" ;;
    esac
    echo
done
