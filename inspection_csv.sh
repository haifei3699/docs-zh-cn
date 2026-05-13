#!/bin/bash

# 系统巡检脚本 - 单行键值对输出格式
# 方便读取入库，字段名包含中英文

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
PROBLEM_LIST=""

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
    PROBLEM_LIST=$(IFS=';'; echo "${PROBLEMS[*]}")
fi

# 处理特殊字符
escape_value() {
    echo "$1" | sed 's/=/\\=/g; s/,/\\,/g; s/\n/ /g'
}

# 输出单行键值对格式，包含中英文字段名
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "时间(Time)=$TIMESTAMP,主机名(Hostname)=$(escape_value "$HOSTNAME"),IP地址(IP)=$(escape_value "$IP"),操作系统(OS)=$(escape_value "$OS"),系统架构(Arch)=$(escape_value "$ARCH"),运行时长(Uptime)=$(escape_value "$UPTIME"),防火墙品牌(FWType)=$(escape_value "$FW_TYPE"),防火墙IP(FWIP)=$(escape_value "$FW_IP"),用户名(Username)=$(escape_value "$FW_USER"),密码(Password)=$(escape_value "$FW_PWD"),base_url=$(escape_value "$FW_BASE_URL"),BDS进程(BDSProcess)=$(escape_value "$BDS_PROCESS"),FwPolicy状态(FwPolicyStatus)=$(escape_value "$FW_POLICY_STATUS"),IP策略数(IPPolicyCount)=$(escape_value "$IP_POLICY_COUNT"),内存使用率(MemUsage)=$(escape_value "$MEM_USAGE"),CPU使用率(CPUUsage)=$(escape_value "$CPU_USAGE"),巡检结果(Result)=$(escape_value "$RESULT"),问题列表(Problems)=$(escape_value "$PROBLEM_LIST")"
