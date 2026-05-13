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
        echo "dump_port: $(get_json_array "$DPDK_CONF" "dump_port")"
        echo "read_threads_per_port: $(get_json_value_num "$DPDK_CONF" "read_threads_per_port")"
        echo "read_threads_sum: $(get_json_value_num "$DPDK_CONF" "read_threads_sum")"
        echo "burst_size: $(get_json_value_num "$DPDK_CONF" "burst_size")"
        echo "ring_size: $(get_json_value_num "$DPDK_CONF" "ring_size")"
        echo "pkt_size: $(get_json_value_num "$DPDK_CONF" "pkt_size")"
    else
        echo "✗ DPDK_driver.json配置文件不存在 ($DPDK_CONF)"
        RESULT="异常"
        PROBLEMS+=("DPDK_driver.json配置文件不存在")
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

echo "1. 进程检查 - BDS进程"
if ps aux | grep -E '[b]ds|BDS' > /dev/null 2>&1; then
    echo "   ✓ BDS进程存在"
    echo "   进程详情:"
    ps aux | grep -E '[b]ds|BDS'
else
    echo "   ✗ BDS进程不存在"
    RESULT="异常"
    PROBLEMS+=("BDS进程不存在")
fi
echo ""

echo "2. 脚本检查 - 系统服务/进程状态"
SCRIPT_PATH="/opt/BDS/exe/check_services.sh"
if [ -f "$SCRIPT_PATH" ]; then
    echo "   ✓ check_services.sh 脚本存在 ($SCRIPT_PATH)"
    echo ""
    echo "   执行脚本检查结果:"
    bash "$SCRIPT_PATH" 2>&1 | while read -r line; do
        echo "      $line"
    done
    
    SCRIPT_EXIT_CODE=$?
    if [ $SCRIPT_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "   ✗ 脚本执行返回异常状态码: $SCRIPT_EXIT_CODE"
        RESULT="异常"
        PROBLEMS+=("check_services.sh脚本执行异常")
    fi
else
    echo "   ✗ check_services.sh 脚本不存在 ($SCRIPT_PATH)"
    RESULT="异常"
    PROBLEMS+=("check_services.sh脚本不存在")
fi

echo ""
echo "3. 防火墙状态"
if command -v iptables > /dev/null 2>&1; then
    BLOCK_COUNT=$(iptables -L -n | grep -c "DROP\|REJECT")
    echo "   防火墙阻断数量: $BLOCK_COUNT"
    if [ $BLOCK_COUNT -gt 0 ]; then
        echo "   警告: 存在防火墙阻断规则"
    fi
elif command -v firewalld > /dev/null 2>&1; then
    BLOCK_COUNT=$(firewall-cmd --list-all | grep -c "deny\|block")
    echo "   防火墙阻断数量: $BLOCK_COUNT"
else
    echo "   ✗ 未检测到防火墙工具"
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
echo "   收包/转发统计:"
echo "   网卡      收包(bytes)    转发(bytes)    收包(Mbps)    转发(Mbps)"
echo "   ---------------------------------------------------------------"
if [ -f "/proc/net/dev" ]; then
    cat /proc/net/dev | grep -v 'lo' | grep -v 'virbr' | grep -E '^[[:space:]]*[a-z]' | while read -r line; do
        iface=$(echo "$line" | awk '{print $1}' | sed 's/://')
        rx=$(echo "$line" | awk '{print $2}')
        tx=$(echo "$line" | awk '{print $10}')
        rx_mbps=$(echo "scale=2; $rx * 8 / 1000000" | bc)
        tx_mbps=$(echo "scale=2; $tx * 8 / 1000000" | bc)
        printf "   %-8s %-14s %-14s %-14s %s\n" "$iface" "$rx" "$tx" "$rx_mbps" "$tx_mbps"
    done
else
    echo "   无法获取流量统计"
fi
echo ""

echo "[DPDK流量]"
DPDK_STATUS="/opt/DPDK_driver/bin/bin/DPDK_status"
if [ -f "$DPDK_STATUS" ] && [ -x "$DPDK_STATUS" ]; then
    echo "   执行DPDK状态检查:"
    "$DPDK_STATUS" -p 2>/dev/null | while read -r line; do
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
