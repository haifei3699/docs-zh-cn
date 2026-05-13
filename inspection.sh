#!/bin/bash

echo "=========================================="
echo "         系统巡检报告"
echo "=========================================="
echo ""

RESULT="正常"
PROBLEMS=()

BDS_CONF="/opt/BDS/conf/BDS.json"
DPDK_CONF="/opt/DPDK_driver/conf/DPDK_driver.json"

get_json_value() {
    local file=$1
    local key=$2
    if [ -f "$file" ]; then
        cat "$file" | grep -oP '"'$key'"\s*:\s*"\K[^"]*' | head -1
    fi
}

get_json_array() {
    local file=$1
    local key=$2
    if [ -f "$file" ]; then
        cat "$file" | grep -A 100 "\"$key\"" | grep -E '\[.*\]' | head -1 | sed 's/\[//;s/\]//;s/"//g'
    fi
}

echo "[一、基本信息]"
echo "巡检日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

get_json_value_num() {
    local file=$1
    local key=$2
    if [ -f "$file" ]; then
        cat "$file" | grep -oP '"'$key'"\s*:\s*\K[0-9]+' | head -1
    fi
}

if [ -f "$BDS_CONF" ]; then
    echo "计算机名: $(get_json_value "$BDS_CONF" "computer_name")"
    echo "设备编号: $(get_json_value "$BDS_CONF" "device_id")"
    echo "使用单位: $(get_json_value "$BDS_CONF" "user_unit")"
    echo "设备型号: $(get_json_value "$BDS_CONF" "device_model")"
    echo "设备版本: $(get_json_value "$BDS_CONF" "device_version")"
    echo "版本类型: $(get_json_value "$BDS_CONF" "version_type")"
    echo "到期日期: $(get_json_value "$BDS_CONF" "expire_date")"
    echo ""
    echo "[BDS.json配置]"
    echo "本地区域(Local Area): $(get_json_value "$BDS_CONF" "local_area")"
    echo "外部标签模式(ExtTagMode): $(get_json_value_num "$BDS_CONF" "extern_tag_mode")"
    echo "NFQ_WebAct启用(NFQ_WebAct): $(get_json_value_num "$BDS_CONF" "NFQ_WebAct_enabled")"
    echo "VPN采样保存天数(VPN Days): $(get_json_value_num "$BDS_CONF" "vpn_sampled_savedays")"
    echo ""
    echo "[DPDK_driver.json配置]"
    if [ -f "$DPDK_CONF" ]; then
        echo "转储端口(Dump Port): $(cat "$DPDK_CONF" | grep -A 5 '"dump_port"' | grep -E '\[.*\]' | head -1 | sed 's/\[//;s/\]//;s/"//g;s/, */, /g')"
        echo "每端口线程数(Threads/Port): $(get_json_value_num "$DPDK_CONF" "read_threads_per_port")"
        echo "线程总数(Threads Total): $(get_json_value_num "$DPDK_CONF" "read_threads_sum")"
        echo "突发大小(Burst Size): $(get_json_value_num "$DPDK_CONF" "burst_size")"
        echo "环形大小(Ring Size): $(get_json_value_num "$DPDK_CONF" "ring_size")"
        echo "数据包大小(Pkt Size): $(get_json_value_num "$DPDK_CONF" "pkt_size")"
    else
        echo "✗ DPDK_driver.json配置文件不存在 ($DPDK_CONF)"
        RESULT="异常"
        PROBLEMS+=("DPDK_driver.json配置文件不存在")
    fi
    echo ""
    echo "[防火墙配置]"
    FW_SETTINGS="/opt/FwPolicy-Manager/settings.ini"
    if [ -f "$FW_SETTINGS" ]; then
        FW_TYPE=$(grep "^FW_TYPE" "$FW_SETTINGS" | head -1 | cut -d'=' -f2 | tr -d ' ')
        echo "防火墙品牌型号: $FW_TYPE"
        
        # 根据FW_TYPE找到对应的Firewall section
        FW_SECTION="Firewall:${FW_TYPE}"
        
        # 提取该section中的配置
        if grep -q "\[$FW_SECTION\]" "$FW_SETTINGS"; then
            # 使用awk提取该section内的内容
            BASE_URL=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^base_url/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            FW_USER=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^user/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            FW_PWD=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^pwd/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            echo "对方防火墙IP: $(echo "$BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|;s|ssh://([^:/]+).*|\1|')"
            echo "用户名: $FW_USER"
            echo "密码: $FW_PWD"
            echo "base_url: $BASE_URL"
        else
            echo "✗ 未找到对应的防火墙配置section: [$FW_SECTION]"
            RESULT="异常"
            PROBLEMS+=("未找到对应防火墙配置")
        fi
    else
        echo "✗ 防火墙配置文件不存在 ($FW_SETTINGS)"
        RESULT="异常"
        PROBLEMS+=("防火墙配置文件不存在")
    fi
    echo ""
    echo "[系统信息]"
    echo "系统IP: $(hostname -I | awk '{print $1}')"
    echo "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "系统架构: $(uname -m)"
    echo "启动时间: $(who -b 2>/dev/null | awk '{print $3, $4}')"

    uptime_sec=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d'.' -f1)
    if [ -n "$uptime_sec" ]; then
        days=$((uptime_sec / 86400))
        hours=$(((uptime_sec % 86400) / 3600))
        echo "运行时长: ${days}天${hours}小时"
    fi
    echo ""
else
    echo "✗ BDS配置文件不存在 ($BDS_CONF)"
    RESULT="异常"
    PROBLEMS+=("BDS配置文件不存在")
    echo ""
    echo "[防火墙配置]"
    FW_SETTINGS="/opt/FwPolicy-Manager/settings.ini"
    if [ -f "$FW_SETTINGS" ]; then
        FW_TYPE=$(grep "^FW_TYPE" "$FW_SETTINGS" | head -1 | cut -d'=' -f2 | tr -d ' ')
        echo "防火墙品牌型号: $FW_TYPE"
        
        # 根据FW_TYPE找到对应的Firewall section
        FW_SECTION="Firewall:${FW_TYPE}"
        
        # 提取该section中的配置
        if grep -q "\[$FW_SECTION\]" "$FW_SETTINGS"; then
            # 使用awk提取该section内的内容
            BASE_URL=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^base_url/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            FW_USER=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^user/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            FW_PWD=$(awk -v sec="[$FW_SECTION]" '
                BEGIN { in_sec=0 }
                $0 ~ sec { in_sec=1; next }
                in_sec && /^\[/ { in_sec=0 }
                in_sec && /^pwd/ { 
                    sub(/^[^=]*=[[:space:]]*/, ""); 
                    gsub(/`/, "");
                    print $0 
                }' "$FW_SETTINGS")
            
            echo "对方防火墙IP: $(echo "$BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|;s|ssh://([^:/]+).*|\1|')"
            echo "用户名: $FW_USER"
            echo "密码: $FW_PWD"
            echo "base_url: $BASE_URL"
        else
            echo "✗ 未找到对应的防火墙配置section: [$FW_SECTION]"
            RESULT="异常"
            PROBLEMS+=("未找到对应防火墙配置")
        fi
    else
        echo "✗ 防火墙配置文件不存在 ($FW_SETTINGS)"
        RESULT="异常"
        PROBLEMS+=("防火墙配置文件不存在")
    fi
    echo ""
    echo "主机名: $(hostname)"
    echo "系统IP: $(hostname -I | awk '{print $1}')"
    echo "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "系统架构: $(uname -m)"
    echo ""
fi

echo "[网络信息]"
echo "网卡信息:"
ip addr show 2>/dev/null | grep -E '^[0-9]+:' | while read -r iface_line; do
    iface=$(echo "$iface_line" | awk -F': ' '{print $2}')
    if [ "$iface" != "lo" ] && [[ ! "$iface" =~ virbr ]]; then
        ipv4=$(ip addr show "$iface" 2>/dev/null | grep -m1 'inet ' | awk '{print $2}')
        mac=$(ip addr show "$iface" 2>/dev/null | grep -m1 'link/ether' | awk '{print $2}')
        if [ -n "$ipv4" ]; then
            echo "   网卡: $iface"
            echo "   IPv4: $ipv4"
            [ -n "$mac" ] && echo "   MAC: $mac"
            echo ""
        fi
    fi
done
echo ""
echo "网关信息: $(ip route show 2>/dev/null | grep default | awk '{print $3}')"
echo "DNS服务器: $(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')"
echo ""

echo "[二、命令行巡检（进程/服务状态）]"
echo ""

echo "1. 系统服务/进程检查"
SCRIPT_PATH="/opt/BDS/exe/check_services.sh"
if [ -f "$SCRIPT_PATH" ]; then
    echo "   ✓ check_services.sh 脚本存在 ($SCRIPT_PATH)"
    echo ""
    echo "   检查结果:"
    bash "$SCRIPT_PATH" 2>&1 | while read -r line; do
        echo "      $line"
    done

    SCRIPT_EXIT_CODE=$?
    if [ $SCRIPT_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "   ✗ 检查执行返回异常状态码: $SCRIPT_EXIT_CODE"
        RESULT="异常"
        PROBLEMS+=("系统服务检查执行异常")
    fi
else
    echo "   ✗ check_services.sh 脚本不存在 ($SCRIPT_PATH)"
    RESULT="异常"
    PROBLEMS+=("check_services.sh脚本不存在")
fi

echo ""
echo "2. 防火墙状态"
FIREWALL_LOG="/opt/FwPolicy-Manager/FireWall.log"
if [ -f "$FIREWALL_LOG" ]; then
    LAST_INFO=$(tail -20 "$FIREWALL_LOG" | grep "当前IP策略数" | tail -1)
    if [ -n "$LAST_INFO" ]; then
        BLOCK_COUNT=$(echo "$LAST_INFO" | sed 's/.*当前IP策略数: //' | awk '{print $1}')
        echo "   防火墙阻断数量: $BLOCK_COUNT"
    else
        echo "   未在日志中找到IP策略数信息"
    fi
else
    echo "   ✗ 防火墙日志文件不存在 ($FIREWALL_LOG)"
    RESULT="异常"
    PROBLEMS+=("防火墙日志文件不存在")
fi
echo ""

echo "3. IP策略数"
if [ -f "$FIREWALL_LOG" ]; then
    if [ -n "$LAST_INFO" ]; then
        echo "   $LAST_INFO"
    else
        echo "   未在日志中找到IP策略数信息"
    fi
else
    echo "   ✗ 防火墙日志文件不存在 ($FIREWALL_LOG)"
fi
echo ""

echo "4. 阻断程序状态"
if systemctl is-active --quiet FwPolicy.service; then
    echo "   ✓ FwPolicy.service 正在运行"
    
    # 获取运行时间
    echo "   阻断程序运行时间:"
    systemctl show FwPolicy.service --property=ActiveEnterTimestamp --value
    
    # 获取重启次数
    echo "   重启次数: $(journalctl -u FwPolicy.service --since "1 week ago" | grep -c "Started FwPolicy")"
    
    # 检查最近错误
    echo "   最近状态:"
    systemctl status FwPolicy.service --no-pager -l | head -10 | sed 's/^/      /'
else
    echo "   ✗ FwPolicy.service 未运行"
    RESULT="异常"
    PROBLEMS+=("FwPolicy.service未运行")
    
    if systemctl status FwPolicy.service --no-pager 2>/dev/null | head -20; then
        echo "   状态信息:"
        systemctl status FwPolicy.service --no-pager -l 2>/dev/null | sed 's/^/      /'
    fi
fi
echo ""

echo "[三、系统监控(System Monitor)]"
echo "----------------------------------------"
echo "内存使用率(Mem%): $(free | grep Mem | awk '{printf "%.1f%%", $3/$2*100}')"
echo "CPU使用率(CPU%): $(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{printf "%.1f%%", 100 - $1}')"
echo ""
echo "网卡运行情况(NIC Status):"
ip link show 2>/dev/null | grep -E '^[0-9]+:' | while read -r line; do
    iface=$(echo "$line" | awk -F': ' '{print $2}')
    status=$(echo "$line" | grep -q 'UP' && echo "UP" || echo "DOWN")
    if [ "$iface" != "lo" ] && [[ ! "$iface" =~ virbr ]]; then
        echo "   $iface: $status"
    fi
done
echo ""
echo "磁盘使用率(Disk%):"
df -h 2>/dev/null | grep -E '^/dev/' | awk '{print "   " $1 ": " $5 " (" $6 ")"}'
echo ""

echo "流量情况(Traffic):"
echo "   【累计流量(系统启动以来)】"
echo "   网卡      收包(bytes)    转发(bytes)    收包累计(M)    转发累计(M)"
echo "   ---------------------------------------------------------------"
if [ -f "/proc/net/dev" ]; then
    cat /proc/net/dev | grep -E '^[[:space:]]*[a-z0-9]+:' | grep -v 'lo:' | while read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/://')
        rx=$(echo "$line" | awk '{print $2}')
        tx=$(echo "$line" | awk '{print $10}')
        if [ -n "$iface" ] && [[ "$iface" =~ ^[a-z] ]]; then
            rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx / 1024 / 1024}")
            tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx / 1024 / 1024}")
            printf "   %-8s %-14s %-14s %-14s %s\n" "$iface" "$rx" "$tx" "$rx_mb" "$tx_mb"
        fi
    done
else
    echo "   无法获取流量统计"
fi

echo ""
echo "   【实时流量(每秒)】"
echo "   网卡      收包(MB)      转发(MB)      收包(Mbps)    转发(Mbps)"
echo "   ---------------------------------------------------------------"
if [ -f "/proc/net/dev" ]; then
    TEMP_FILE=$(mktemp)
    
    cat /proc/net/dev | grep -E '^[[:space:]]*[a-z0-9]+:' | grep -v 'lo:' > "$TEMP_FILE"
    
    sleep 1
    
    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/://')
        rx1=$(echo "$line" | awk '{print $2}')
        tx1=$(echo "$line" | awk '{print $10}')
        
        line2=$(cat /proc/net/dev | grep "$iface:")
        if [ -n "$line2" ]; then
            rx2=$(echo "$line2" | awk '{print $2}')
            tx2=$(echo "$line2" | awk '{print $10}')
            
            rx_diff=$((rx2 - rx1))
            tx_diff=$((tx2 - tx1))
            
            rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_diff / 1024 / 1024}")
            tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_diff / 1024 / 1024}")
            rx_mbps=$(awk "BEGIN {printf \"%.2f\", $rx_diff * 8 / 1000000}")
            tx_mbps=$(awk "BEGIN {printf \"%.2f\", $tx_diff * 8 / 1000000}")
            
            printf "   %-8s %-14s %-14s %-14s %s\n" "$iface" "$rx_mb" "$tx_mb" "$rx_mbps" "$tx_mbps"
        fi
    done < "$TEMP_FILE"
    
    rm -f "$TEMP_FILE"
else
    echo "   无法获取流量统计"
fi
echo ""

echo "[DPDK流量]"
DPDK_STATUS="/opt/DPDK_driver/bin/DPDK_status"
if [ -f "$DPDK_STATUS" ] && [ -x "$DPDK_STATUS" ]; then
    echo "   |端口   | 收包数       | 收包字节        | 丢包数         | 丢包字节       | 错误包数       | 速度(M) |"
    "$DPDK_STATUS" -p 2>/dev/null | while IFS= read -r line; do
        echo "   $line"
    done
else
    echo "   ✗ DPDK状态检查工具不存在或不可执行 ($DPDK_STATUS)"
    RESULT="异常"
    PROBLEMS+=("DPDK状态检查工具不存在")
fi
echo ""

echo "[四、磁盘空间检查(Disk Space)]"
df -h | grep -E '^/dev/'
echo ""

echo "[五、内存使用检查(Memory)]"
free -h
echo ""

echo "[六、CPU负载检查(CPU Load)]"
echo "CPU负载: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

echo "=========================================="
echo "[巡检汇总]"
echo ""
echo "【巡检总结】: $RESULT"
if [ "$RESULT" = "异常" ]; then
    echo "【问题详情】:"
    for i in "${!PROBLEMS[@]}"; do
        echo "   $((i+1)). ${PROBLEMS[$i]}"
    done
    echo ""
    echo "【整改建议】: 需要尽快处理"
else
    echo "【整改建议】: 无"
fi
echo "=========================================="
