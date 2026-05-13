#!/bin/bash

# 系统巡检脚本 - 完整信息CSV输出
# 包含所有巡检信息，一行输出

# 初始化变量
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
GATEWAY=$(ip route show 2>/dev/null | grep default | awk '{print $3}')
DNS=$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

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

# 进程检查
BDS_PROCESS="否"
ps aux | grep -E '[b]ds|BDS' > /dev/null 2>&1 && BDS_PROCESS="是"

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

# DPDK流量
DPDK_RX_PKTS="0"
DPDK_RX_BYTE="0"
DPDK_SPEED="0"
DPDK_STATUS="/opt/DPDK_driver/bin/DPDK_status"
if [ -f "$DPDK_STATUS" ] && [ -x "$DPDK_STATUS" ]; then
    DPDK_OUTPUT=$("$DPDK_STATUS" -p 2>/dev/null | grep -A 5 'Total')
    DPDK_RX_PKTS=$(echo "$DPDK_OUTPUT" | grep 'Total' | awk '{print $2}')
    DPDK_RX_BYTE=$(echo "$DPDK_OUTPUT" | grep 'Total' | awk '{print $3}')
    DPDK_SPEED=$(echo "$DPDK_OUTPUT" | grep 'Total' | awk '{print $NF}')
fi

# 检查异常
PROBLEMS=()
[ -z "$FW_IP" ] && PROBLEMS+=("防火墙IP未配置")
[ -z "$FW_USER" ] && PROBLEMS+=("防火墙用户名未配置")
[ "$BDS_PROCESS" = "否" ] && PROBLEMS+=("BDS进程未运行")
[ "$FW_POLICY_STATUS" != "运行中" ] && PROBLEMS+=("FwPolicy服务未运行")

RESULT="正常"
SUGGESTION="无"
if [ ${#PROBLEMS[@]} -gt 0 ]; then
    RESULT="异常"
    SUGGESTION="需要尽快处理"
fi
PROBLEM_LIST=$(IFS=';'; echo "${PROBLEMS[*]}")

# 处理特殊字符
escape_csv() {
    local val="$1"
    if [[ "$val" == *","* || "$val" == *"\""* || "$val" == *$'\n'* ]]; then
        echo "\"${val//\"/\"\"}\""
    else
        echo "$val"
    fi
}

# 输出CSV头
echo "巡检日期(Time),主机名(Hostname),IP地址(IP),操作系统(OS),系统架构(Arch),启动时间(BootTime),运行时长(Uptime),网关(Gateway),DNS(DNS),本地区域(LocalArea),外部标签模式(ExtTagMode),NFQ_WebAct启用(NFQWebAct),VPN采样天数(VPNDays),转储端口(DumpPort),每端口线程数(ThreadsPerPort),线程总数(ThreadsTotal),突发大小(BurstSize),环形大小(RingSize),数据包大小(PktSize),防火墙品牌(FWType),防火墙IP(FWIP),用户名(FWUser),密码(FWPassword),base_url(FWBaseURL),BDS进程(BDSProcess),FwPolicy状态(FwPolicyStatus),FwPolicy运行时间(FwPolicyUptime),FwPolicy重启次数(FwPolicyRestarts),IP策略数(IPPolicyCount),内存使用率(MemUsage),CPU使用率(CPUUsage),CPU负载(CPULoad),磁盘使用率(DiskUsage),网卡状态(NICStatus),DPDK收包数(DPDKRxPkts),DPDK收包字节(DPDKRxByte),DPDK速度(DPDKSpeed),巡检结果(Result),整改建议(Suggestion),问题列表(Problems)"

# 输出CSV数据
echo "$(escape_csv "$TIMESTAMP"),$(escape_csv "$HOSTNAME"),$(escape_csv "$IP"),$(escape_csv "$OS"),$(escape_csv "$ARCH"),$(escape_csv "$BOOT_TIME"),$(escape_csv "$UPTIME"),$(escape_csv "$GATEWAY"),$(escape_csv "$DNS"),$(escape_csv "$LOCAL_AREA"),$(escape_csv "$EXT_TAG_MODE"),$(escape_csv "$NFQ_WEBACT"),$(escape_csv "$VPN_DAYS"),$(escape_csv "$DUMP_PORT"),$(escape_csv "$READ_THREADS_PER_PORT"),$(escape_csv "$READ_THREADS_SUM"),$(escape_csv "$BURST_SIZE"),$(escape_csv "$RING_SIZE"),$(escape_csv "$PKT_SIZE"),$(escape_csv "$FW_TYPE"),$(escape_csv "$FW_IP"),$(escape_csv "$FW_USER"),$(escape_csv "$FW_PWD"),$(escape_csv "$FW_BASE_URL"),$(escape_csv "$BDS_PROCESS"),$(escape_csv "$FW_POLICY_STATUS"),$(escape_csv "$FW_POLICY_UPTIME"),$(escape_csv "$FW_POLICY_RESTARTS"),$(escape_csv "$IP_POLICY_COUNT"),$(escape_csv "$MEM_USAGE"),$(escape_csv "$CPU_USAGE"),$(escape_csv "$CPU_LOAD"),$(escape_csv "$DISK_USAGE"),$(escape_csv "$NIC_STATUS"),$(escape_csv "$DPDK_RX_PKTS"),$(escape_csv "$DPDK_RX_BYTE"),$(escape_csv "$DPDK_SPEED"),$(escape_csv "$RESULT"),$(escape_csv "$SUGGESTION"),$(escape_csv "$PROBLEM_LIST")"
