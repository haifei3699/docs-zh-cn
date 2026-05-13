#!/bin/bash

# 系统巡检脚本 - CSV单行输出格式
# 方便读取入库

# 初始化变量
HOSTNAME=""
IP=""
OS=""
ARCH=""
UPTIME=""
FW_TYPE=""
FW_IP=""
FW_USER=""
FW_PWD=""
FW_BASE_URL=""
BDS_PROCESS="否"
FW_POLICY_STATUS="未运行"
IP_POLICY_COUNT="0"
MEM_USAGE=""
CPU_USAGE=""
RESULT="正常"

# 获取基本信息
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
ARCH=$(uname -m)

# 获取运行时长
uptime_sec=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d'.' -f1)
if [ -n "$uptime_sec" ]; then
    days=$((uptime_sec / 86400))
    hours=$(((uptime_sec % 86400) / 3600))
    UPTIME="${days}天${hours}小时"
fi

# 获取防火墙配置
FW_SETTINGS="/opt/FwPolicy-Manager/settings.ini"
if [ -f "$FW_SETTINGS" ]; then
    FW_TYPE=$(grep "^FW_TYPE" "$FW_SETTINGS" | head -1 | cut -d'=' -f2 | tr -d ' ')
    FW_SECTION="Firewall:${FW_TYPE}"
    
    if grep -q "^\[$FW_SECTION\]" "$FW_SETTINGS"; then
        start_line=$(grep -n "^\[$FW_SECTION\]" "$FW_SETTINGS" | cut -d':' -f1)
        next_section=$(awk -v start=$start_line 'NR > start && /^\[/ { print NR; exit }' "$FW_SETTINGS")
        if [ -z "$next_section" ]; then
            next_section=$(wc -l < "$FW_SETTINGS")
            next_section=$((next_section + 1))
        fi
        
        section_content=$(sed -n "$((start_line+1)),$((next_section-1))p" "$FW_SETTINGS")
        FW_BASE_URL=$(echo "$section_content" | grep "^base_url" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_USER=$(echo "$section_content" | grep "^user" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_PWD=$(echo "$section_content" | grep "^pwd" | head -1 | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/`//g')
        FW_IP=$(echo "$FW_BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|;s|ssh://([^:/]+).*|\1|')
    fi
fi

# 检查BDS进程
if ps aux | grep -E '[b]ds|BDS' > /dev/null 2>&1; then
    BDS_PROCESS="是"
fi

# 检查FwPolicy服务
if systemctl is-active --quiet FwPolicy.service; then
    FW_POLICY_STATUS="运行中"
fi

# 获取IP策略数
FIREWALL_LOG="/opt/FwPolicy-Manager/FireWall.log"
if [ -f "$FIREWALL_LOG" ]; then
    LAST_INFO=$(tac "$FIREWALL_LOG" | grep "分线等级2" -m 1)
    if [ -n "$LAST_INFO" ]; then
        IP_POLICY_COUNT=$(echo "$LAST_INFO" | sed 's/.*当前IP策略数: //' | awk '{print $1}')
    fi
fi

# 获取系统资源使用
MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2*100}')
CPU_USAGE=$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{printf "%.1f%%", 100 - $1}')

# 检查异常
PROBLEMS=()
if [ -z "$FW_IP" ] || [ -z "$FW_USER" ]; then
    PROBLEMS+=("防火墙配置不完整")
fi
if [ "$BDS_PROCESS" = "否" ]; then
    PROBLEMS+=("BDS进程未运行")
fi
if [ "$FW_POLICY_STATUS" != "运行中" ]; then
    PROBLEMS+=("FwPolicy服务未运行")
fi

if [ ${#PROBLEMS[@]} -gt 0 ]; then
    RESULT="异常"
fi

# 输出CSV格式（单行）
# 字段顺序：时间,主机名,IP,操作系统,架构,运行时长,防火墙品牌,防火墙IP,用户名,密码,base_url,BDS进程,FwPolicy状态,IP策略数,内存使用率,CPU使用率,巡检结果,问题列表

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
PROBLEM_LIST=$(IFS=';'; echo "${PROBLEMS[*]}")

# 处理特殊字符，确保CSV格式正确
escape_csv() {
    echo "$1" | sed 's/"/""/g; s/,/\\,/g; s/\n/ /g'
}

echo "$TIMESTAMP,$(escape_csv "$HOSTNAME"),$(escape_csv "$IP"),$(escape_csv "$OS"),$(escape_csv "$ARCH"),$(escape_csv "$UPTIME"),$(escape_csv "$FW_TYPE"),$(escape_csv "$FW_IP"),$(escape_csv "$FW_USER"),$(escape_csv "$FW_PWD"),$(escape_csv "$FW_BASE_URL"),$(escape_csv "$BDS_PROCESS"),$(escape_csv "$FW_POLICY_STATUS"),$(escape_csv "$IP_POLICY_COUNT"),$(escape_csv "$MEM_USAGE"),$(escape_csv "$CPU_USAGE"),$(escape_csv "$RESULT"),$(escape_csv "$PROBLEM_LIST")"
