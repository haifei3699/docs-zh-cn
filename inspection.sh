#!/bin/bash

echo "=========================================="
echo "         系统巡检报告"
echo "=========================================="
echo ""

RESULT="正常"
PROBLEMS=()

echo "[一、基本信息]"
echo "巡检日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机名: $(hostname)"
echo ""
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
echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "内核版本: $(uname -r)"
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

echo "[三、磁盘空间检查]"
df -h | grep -E '^/dev/'
echo ""

echo "[四、内存使用检查]"
free -h
echo ""

echo "[五、CPU负载检查]"
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