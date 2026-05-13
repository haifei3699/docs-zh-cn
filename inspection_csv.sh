#!/bin/bash

# 系统巡检脚本 - 竖排键值对格式输出
# 左边名称，右边值，更易阅读

# 输出函数
print_field() {
    printf "%-20s %s\n" "$1" "$2"
}

# 获取数据
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
ARCH=$(uname -m)

# 运行时长
uptime_sec=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d'.' -f1)
if [ -n "$uptime_sec" ]; then
    days=$((uptime_sec / 86400))
    hours=$(((uptime_sec % 86400) / 3600))
    UPTIME="${days}天${hours}小时"
fi

# 启动时间
BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}')

# 网关和DNS
DNS=$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

# 获取所有网卡信息（包括IP、网关、MAC）
NETWORK_INFO=""
for iface in $(ip link show 2>/dev/null | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | awk '{print $1}' | grep -v 'lo' | grep -v 'virbr'); do
    # 清理接口名（去除 @ 后面的部分）
    clean_iface=$(echo "$iface" | sed 's/@.*//')
    ipv4=$(ip addr show "$clean_iface" 2>/dev/null | grep -m1 'inet ' | awk '{print $2}')
    mac=$(ip addr show "$clean_iface" 2>/dev/null | grep -m1 'link/ether' | awk '{print $2}')
    # 获取该网卡的网关
    gateway=$(ip route show 2>/dev/null | grep "dev $clean_iface" | grep default | awk '{print $3}')
    if [ -n "$ipv4" ]; then
        # 使用 | 作为分隔符，避免与MAC地址中的冒号冲突
        NETWORK_INFO="${NETWORK_INFO}${clean_iface}|${ipv4}|${mac}|${gateway};"
    fi
done
NETWORK_INFO=$(echo "$NETWORK_INFO" | sed 's/;$//')

# BDS.json配置
BDS_CONF="/opt/BDS/conf/BDS.json"
if [ -f "$BDS_CONF" ]; then
    LOCAL_AREA=$(cat "$BDS_CONF" | grep -oP '"local_area"\s*:\s*"\K[^"]*' | head -1)
    EXT_TAG_MODE=$(cat "$BDS_CONF" | grep -oP '"extern_tag_mode"\s*:\s*\K[0-9]+' | head -1)
    NFQ_WEBACT=$(cat "$BDS_CONF" | grep -oP '"NFQ_WebAct_enabled"\s*:\s*\K[0-9]+' | head -1)
    VPN_DAYS=$(cat "$BDS_CONF" | grep -oP '"vpn_sampled_savedays"\s*:\s*\K[0-9]+' | head -1)
fi

# DPDK配置
DPDK_CONF="/opt/DPDK_driver/conf/DPDK_driver.json"
if [ -f "$DPDK_CONF" ]; then
    DUMP_PORT=$(cat "$DPDK_CONF" | grep -A 5 '"dump_port"' | grep -E '\[.*\]' | head -1 | sed 's/\[//;s/\]//;s/"//g;s/, */, /g')
    READ_THREADS_PER_PORT=$(cat "$DPDK_CONF" | grep -oP '"read_threads_per_port"\s*:\s*\K[0-9]+' | head -1)
    READ_THREADS_SUM=$(cat "$DPDK_CONF" | grep -oP '"read_threads_sum"\s*:\s*\K[0-9]+' | head -1)
    BURST_SIZE=$(cat "$DPDK_CONF" | grep -oP '"burst_size"\s*:\s*\K[0-9]+' | head -1)
    RING_SIZE=$(cat "$DPDK_CONF" | grep -oP '"ring_size"\s*:\s*\K[0-9]+' | head -1)
    PKT_SIZE=$(cat "$DPDK_CONF" | grep -oP '"pkt_size"\s*:\s*\K[0-9]+' | head -1)
fi

# 防火墙配置
FW_SETTINGS="/opt/FwPolicy-Manager/settings.ini"
if [ -f "$FW_SETTINGS" ]; then
    FW_TYPE=$(grep "^FW_TYPE" "$FW_SETTINGS" | head -1 | cut -d'=' -f2 | tr -d ' ')
    FW_SECTION="Firewall:${FW_TYPE}"
    
    if grep -q "^\[$FW_SECTION\]" "$FW_SETTINGS"; then
        start_line=$(grep -n "^\[$FW_SECTION\]" "$FW_SETTINGS" | cut -d':' -f1)
        next_section=$(awk -v start=$start_line 'NR > start && /^\[/ { print NR; exit }' "$FW_SETTINGS")
        [ -z "$next_section" ] && next_section=$(( $(wc -l < "$FW_SETTINGS") + 1 ))
        
        section_content=$(sed -n "$((start_line+1)),$((next_section-1))p" "$FW_SETTINGS")
        FW_BASE_URL=$(echo "$section_content" | grep "^base_url" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_USER=$(echo "$section_content" | grep "^user" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_PWD=$(echo "$section_content" | grep "^pwd" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_IP=$(echo "$FW_BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|;s|ssh://([^:/]+).*|\1|')
    fi
fi

# 服务进程检查
# DPDK
DPDK_COUNT=$(ps aux | grep -i 'DPDK_driver' | grep -v grep | wc -l)
DPDK_STATUS=$( [ "$DPDK_COUNT" -ge 1 ] && echo "正常($DPDK_COUNT)" || echo "异常(0)" )

# RunServiceShell
RUN_COUNT=$(ps aux | grep 'RunServiceShell' | grep -v grep | wc -l)
RUN_STATUS=$( [ "$RUN_COUNT" -ge 1 ] && echo "正常($RUN_COUNT)" || echo "异常(0)" )

# nginx
NGINX_COUNT=$(ps aux | grep 'nginx' | grep -v grep | wc -l)
NGINX_STATUS=$( [ "$NGINX_COUNT" -ge 1 ] && echo "正常($NGINX_COUNT)" || echo "异常(0)" )

# clickhouse
CLICKHOUSE_COUNT=$(ps aux | grep 'clickhouse-server' | grep -v grep | wc -l)
CLICKHOUSE_STATUS=$( [ "$CLICKHOUSE_COUNT" -ge 1 ] && echo "正常($CLICKHOUSE_COUNT)" || echo "异常(0)" )

# elasticsearch
ES_COUNT=$(ps aux | grep 'elasticsearch' | grep -v grep | wc -l)
ES_STATUS=$( [ "$ES_COUNT" -ge 1 ] && echo "正常($ES_COUNT)" || echo "异常(0)" )

# redis
REDIS_COUNT=$(ps aux | grep 'redis-server' | grep -v grep | wc -l)
REDIS_STATUS=$( [ "$REDIS_COUNT" -ge 1 ] && echo "正常($REDIS_COUNT)" || echo "异常(0)" )

# bdsweb
BDSWEB_COUNT=$(ps aux | grep 'bdsweb' | grep -v grep | wc -l)
BDSWEB_STATUS=$( [ "$BDSWEB_COUNT" -ge 5 ] && echo "正常($BDSWEB_COUNT)" || echo "异常($BDSWEB_COUNT)" )

# BDS2Weka
WEKA_COUNT=$(ps aux | grep 'BDS2Weka' | grep -v grep | wc -l)
WEKA_STATUS=$( [ "$WEKA_COUNT" -ge 2 ] && echo "正常($WEKA_COUNT)" || echo "异常($WEKA_COUNT)" )

# BDS进程检查 - 需要多个进程
BDS_ACT_COUNT=$(ps aux | grep 'BDS_ACT' | grep -v grep | wc -l)
BDS_HOST_COUNT=$(ps aux | grep 'BDS_HOST' | grep -v grep | wc -l)
BDS_SRV_COUNT=$(ps aux | grep 'BDS_SRV' | grep -v grep | wc -l)
BDS_DATA_COUNT=$(ps aux | grep 'BDS_DATA' | grep -v grep | wc -l)
BDS_PCAP_COUNT=$(ps aux | grep 'BDS_PCAP' | grep -v grep | wc -l)
BDS_MAIN_COUNT=$(ps aux | grep './BDS' | grep -v grep | wc -l)
BDS_TOTAL_COUNT=$((BDS_ACT_COUNT + BDS_HOST_COUNT + BDS_SRV_COUNT + BDS_DATA_COUNT + BDS_PCAP_COUNT + BDS_MAIN_COUNT))

# 检查BDS进程是否完整
BDS_STATUS="异常"
if [ "$BDS_ACT_COUNT" -ge 1 ] && [ "$BDS_HOST_COUNT" -ge 1 ] && [ "$BDS_SRV_COUNT" -ge 1 ] && [ "$BDS_DATA_COUNT" -ge 10 ] && [ "$BDS_PCAP_COUNT" -ge 1 ] && [ "$BDS_MAIN_COUNT" -ge 1 ]; then
    BDS_STATUS="正常($BDS_TOTAL_COUNT)"
else
    BDS_STATUS="异常(ACT:$BDS_ACT_COUNT,HOST:$BDS_HOST_COUNT,SRV:$BDS_SRV_COUNT,DATA:$BDS_DATA_COUNT,PCAP:$BDS_PCAP_COUNT,MAIN:$BDS_MAIN_COUNT)"
fi

# FwPolicy服务状态
FW_POLICY_STATUS="未运行"
FW_POLICY_UPTIME=""
FW_POLICY_RESTARTS="0"
if systemctl is-active --quiet FwPolicy.service; then
    FW_POLICY_STATUS="运行中"
    FW_POLICY_UPTIME=$(systemctl show FwPolicy.service --property=ActiveEnterTimestamp --value 2>/dev/null)
    FW_POLICY_RESTARTS=$(journalctl -u FwPolicy.service --since "1 week ago" 2>/dev/null | grep -c "Started FwPolicy" || echo "0")
fi

# IP策略数
IP_POLICY_COUNT="0"
FIREWALL_LOG="/opt/FwPolicy-Manager/FireWall.log"
if [ -f "$FIREWALL_LOG" ]; then
    LAST_INFO=$(tac "$FIREWALL_LOG" | grep "分线等级2" -m 1 2>/dev/null)
    [ -n "$LAST_INFO" ] && IP_POLICY_COUNT=$(echo "$LAST_INFO" | sed 's/.*当前IP策略数: //' | awk '{print $1}')
fi

# 系统资源
MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2*100}')
CPU_USAGE=$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{printf "%.1f%%", 100 - $1}')
CPU_LOAD=$(top -bn1 | head -1 | awk '{print $10","$11","$12}')

# 磁盘使用率
DISK_USAGE=$(df -h 2>/dev/null | grep -E '^/dev/' | awk '{print $1":"$5":"$6}' | tr '\n' ';' | sed 's/;$//')

# 网卡状态
NIC_STATUS=$(ip link show 2>/dev/null | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v 'lo' | grep -v 'virbr' | tr '\n' ',' | sed 's/,$//')

# DPDK流量 - 只记录速度
DPDK_SPEED="0"
DPDK_STATUS="/opt/DPDK_driver/bin/DPDK_status"
if [ -f "$DPDK_STATUS" ] && [ -x "$DPDK_STATUS" ]; then
    # 获取DPDK状态输出
    DPDK_FULL_OUTPUT=$("$DPDK_STATUS" -p 2>/dev/null)
    if [ -n "$DPDK_FULL_OUTPUT" ]; then
        # 尝试多种方式获取速度值
        # 方式1: 从Total行获取最后一个字段
        DPDK_SPEED=$(echo "$DPDK_FULL_OUTPUT" | grep -i 'total' | tail -1 | awk '{print $NF}')
        # 如果为空，尝试方式2: 查找Speed(M)列
        if [ -z "$DPDK_SPEED" ] || [ "$DPDK_SPEED" = "0" ]; then
            DPDK_SPEED=$(echo "$DPDK_FULL_OUTPUT" | grep -E '\|[0-9]+\s*\|' | tail -1 | awk '{print $NF}')
        fi
        # 方式3: 直接提取数字
        if [ -z "$DPDK_SPEED" ] || [ "$DPDK_SPEED" = "0" ]; then
            DPDK_SPEED=$(echo "$DPDK_FULL_OUTPUT" | grep -oP 'Speed\(M\)\s*\|\s*\K[0-9]+' | tail -1)
        fi
    fi
fi
# 确保有值
[ -z "$DPDK_SPEED" ] && DPDK_SPEED="0"

# 检查异常
PROBLEMS=()
[ -z "$FW_IP" ] && PROBLEMS+=("防火墙IP未配置")
[ -z "$FW_USER" ] && PROBLEMS+=("防火墙用户名未配置")

# 检查各服务状态
[[ "$DPDK_STATUS" == 异常* ]] && PROBLEMS+=("DPDK异常")
[[ "$RUN_STATUS" == 异常* ]] && PROBLEMS+=("RunServiceShell异常")
[[ "$NGINX_STATUS" == 异常* ]] && PROBLEMS+=("nginx异常")
[[ "$CLICKHOUSE_STATUS" == 异常* ]] && PROBLEMS+=("clickhouse异常")
[[ "$ES_STATUS" == 异常* ]] && PROBLEMS+=("elasticsearch异常")
[[ "$REDIS_STATUS" == 异常* ]] && PROBLEMS+=("redis异常")
[[ "$BDSWEB_STATUS" == 异常* ]] && PROBLEMS+=("bdsweb异常")
[[ "$WEKA_STATUS" == 异常* ]] && PROBLEMS+=("BDS2Weka异常")
[[ "$BDS_STATUS" == 异常* ]] && PROBLEMS+=("BDS进程异常")
[ "$FW_POLICY_STATUS" != "运行中" ] && PROBLEMS+=("FwPolicy服务未运行")

RESULT="正常"
SUGGESTION="无"
if [ ${#PROBLEMS[@]} -gt 0 ]; then
    RESULT="异常"
    SUGGESTION="需要尽快处理"
fi
PROBLEM_LIST=$(IFS=';'; echo "${PROBLEMS[*]}")

# 输出竖排格式
echo "=========================================="
echo "【系统巡检报告】"
echo "=========================================="
echo ""

echo "[基本信息]"
print_field "巡检日期:" "$TIMESTAMP"
print_field "主机名:" "$HOSTNAME"
print_field "操作系统:" "$OS"
print_field "系统架构:" "$ARCH"
print_field "启动时间:" "$BOOT_TIME"
print_field "运行时长:" "$UPTIME"
echo ""

echo "[网络信息]"
# DNS服务器单独显示
DNS1=$(echo "$DNS" | cut -d',' -f1)
DNS2=$(echo "$DNS" | cut -d',' -f2)
print_field "DNS1:" "$DNS1"
[ -n "$DNS2" ] && print_field "DNS2:" "$DNS2"

# 显示每个网卡的信息（每个字段单独一行）
IFS=';' read -ra NET_ARRAY <<< "$NETWORK_INFO"
for net_item in "${NET_ARRAY[@]}"; do
    IFS='|' read -ra NET_PARTS <<< "$net_item"
    iface_name="${NET_PARTS[0]}"
    if [ -n "$iface_name" ]; then
        print_field "网卡${iface_name}IP:" "${NET_PARTS[1]}"
        print_field "网卡${iface_name}MAC:" "${NET_PARTS[2]}"
        print_field "网卡${iface_name}网关:" "${NET_PARTS[3]}"
    fi
done
echo ""

echo "[BDS.json配置]"
print_field "本地区域:" "$LOCAL_AREA"
print_field "外部标签模式:" "$EXT_TAG_MODE"
print_field "NFQ_WebAct启用:" "$NFQ_WEBACT"
print_field "VPN采样天数:" "$VPN_DAYS"
echo ""

echo "[DPDK配置]"
print_field "转储端口:" "$DUMP_PORT"
print_field "每端口线程数:" "$READ_THREADS_PER_PORT"
print_field "线程总数:" "$READ_THREADS_SUM"
print_field "突发大小:" "$BURST_SIZE"
print_field "环形大小:" "$RING_SIZE"
print_field "数据包大小:" "$PKT_SIZE"
echo ""

echo "[防火墙配置]"
print_field "防火墙品牌:" "$FW_TYPE"
print_field "防火墙IP:" "$FW_IP"
print_field "用户名:" "$FW_USER"
print_field "密码:" "$FW_PWD"
print_field "base_url:" "$FW_BASE_URL"
echo ""

echo "[服务状态]"
print_field "DPDK:" "$DPDK_STATUS"
print_field "RunServiceShell:" "$RUN_STATUS"
print_field "nginx:" "$NGINX_STATUS"
print_field "clickhouse:" "$CLICKHOUSE_STATUS"
print_field "elasticsearch:" "$ES_STATUS"
print_field "redis:" "$REDIS_STATUS"
print_field "bdsweb:" "$BDSWEB_STATUS"
print_field "BDS2Weka:" "$WEKA_STATUS"
print_field "BDS进程:" "$BDS_STATUS"
print_field "FwPolicy状态:" "$FW_POLICY_STATUS"
print_field "FwPolicy运行时间:" "$FW_POLICY_UPTIME"
print_field "FwPolicy重启次数:" "$FW_POLICY_RESTARTS"
print_field "IP策略数:" "$IP_POLICY_COUNT"
echo ""

echo "[系统资源]"
print_field "内存使用率:" "$MEM_USAGE"
print_field "CPU使用率:" "$CPU_USAGE"
print_field "CPU负载:" "$CPU_LOAD"
print_field "磁盘使用率:" "$DISK_USAGE"
print_field "网卡状态:" "$NIC_STATUS"
echo ""

echo "[DPDK流量]"
print_field "速度(Mbps):" "$DPDK_SPEED"
echo ""

echo "=========================================="
print_field "【巡检结果】:" "$RESULT"
print_field "【整改建议】:" "$SUGGESTION"
if [ -n "$PROBLEM_LIST" ]; then
    print_field "【问题列表】:" "$PROBLEM_LIST"
fi
echo "=========================================="
