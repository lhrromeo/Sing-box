#!/usr/bin/env bash

export LANG=en_US.UTF-8

# 颜色定义
re="\033[0m"
red() { echo -e "\e[1;91m$1$re"; }
green() { echo -e "\e[1;32m$1$re"; }
purple() { echo -e "\e[1;35m$1$re"; }
reading() { read -p "$(red "$1")" "$2"; }

# 路径
work_dir="$HOME/.sing-box"
config_dir="$work_dir/config.json"
mkdir -p "$work_dir"
chmod 700 "$work_dir"
export vless_port=${PORT:-$(shuf -i 10000-65000 -n 1)}

# 安装 sing-box
install_singbox() {
    purple "正在安装 sing-box..."
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64) ARCH=amd64 ;;
        aarch64|arm64) ARCH=arm64 ;;
        armv7l) ARCH=armv7 ;;
        i386|i686) ARCH=386 ;;
        *) red "不支持的架构: $ARCH_RAW"; return ;;
    esac

    curl -sLo "$work_dir/sing-box" "https://$ARCH.ssss.nyc.mn/sbx"
    curl -sLo "$work_dir/argo" "https://$ARCH.ssss.nyc.mn/bot"
    curl -sLo "$work_dir/qrencode" "https://$ARCH.ssss.nyc.mn/qrencode"
    chmod +x "$work_dir/"*

    uuid=$(cat /proc/sys/kernel/random/uuid)
    password=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24)
    output=$("$work_dir/sing-box" generate reality-keypair)
    private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')

    nginx_port=$(($vless_port + 1))
    tuic_port=$(($vless_port + 2))
    hy2_port=$(($vless_port + 3))

    openssl ecparam -genkey -name prime256v1 -out "$work_dir/private.key"
    openssl req -new -x509 -days 3650 -key "$work_dir/private.key" -out "$work_dir/cert.pem" -subj "/CN=bing.com"

cat > "$config_dir" <<EOF
{
  "log": { "disabled": false, "level": "error", "output": "$work_dir/sb.log" },
  "dns": { "servers": [{ "tag": "local", "address": "local" }] },
  "inbounds": [
    { "type": "vless", "tag": "vless-reality", "listen": "::", "listen_port": $vless_port,
      "users": [{ "uuid": "$uuid", "flow": "xtls-rprx-vision" }],
      "tls": { "enabled": true, "server_name": "www.iij.ad.jp",
        "reality": { "enabled": true, "handshake": { "server": "www.iij.ad.jp", "server_port": 443 },
        "private_key": "$private_key", "short_id": [""] } } },
    { "type": "vmess", "tag": "vmess-ws", "listen": "::", "listen_port": 8001,
      "users": [{ "uuid": "$uuid" }], "transport": { "type": "ws", "path": "/vmess-argo" } },
    { "type": "hysteria2", "tag": "hysteria2", "listen": "::", "listen_port": $hy2_port,
      "users": [{ "password": "$uuid" }],
      "tls": { "enabled": true, "certificate_path": "$work_dir/cert.pem", "key_path": "$work_dir/private.key" } },
    { "type": "tuic", "tag": "tuic", "listen": "::", "listen_port": $tuic_port,
      "users": [{ "uuid": "$uuid", "password": "$password" }],
      "tls": { "enabled": true, "certificate_path": "$work_dir/cert.pem", "key_path": "$work_dir/private.key" } }
  ],
  "outbounds": [ {"type": "direct", "tag": "direct"} ]
}
EOF

    green "安装完成，配置文件路径: $config_dir"
}

# 启动/停止函数
start_singbox() {
    nohup "$work_dir/sing-box" run -c "$config_dir" >"$work_dir/singbox.log" 2>&1 &
    echo $! > "$work_dir/singbox.pid"
    green "sing-box 已启动 (PID: $(cat $work_dir/singbox.pid))"
}

stop_singbox() {
    kill "$(cat $work_dir/singbox.pid 2>/dev/null)" 2>/dev/null && rm -f "$work_dir/singbox.pid"
    green "sing-box 已停止"
}

restart_singbox() { stop_singbox; sleep 1; start_singbox; }

start_sub_server() {
    cd "$work_dir"
    nohup python3 -m http.server 8080 >"$work_dir/http.log" 2>&1 &
    echo $! > "$work_dir/http.pid"
    green "订阅服务已启动: http://127.0.0.1:8080/sub.txt"
}

stop_sub_server() {
    kill "$(cat $work_dir/http.pid 2>/dev/null)" 2>/dev/null && rm -f "$work_dir/http.pid"
    green "订阅服务已停止"
}

# 打印菜单一次
print_menu() {
    purple "=== sing-box 用户模式管理器 ==="
    echo "1. 安装 sing-box"
    echo "2. 启动 sing-box"
    echo "3. 停止 sing-box"
    echo "4. 重启 sing-box"
    echo "5. 启动订阅服务"
    echo "6. 停止订阅服务"
    echo "0. 退出"
}

# 无限循环菜单，不闪动
while true; do
    print_menu
    reading "请输入选择: " choice
    case "$choice" in
        1) install_singbox ;;
        2) start_singbox ;;
        3) stop_singbox ;;
        4) restart_singbox ;;
        5) start_sub_server ;;
        6) stop_sub_server ;;
        0) exit 0 ;;
        *) red "无效选择" ;;
    esac
    reading "操作完成，按回车返回菜单..." dummy
    echo
done
