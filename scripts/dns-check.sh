#!/usr/bin/env bash
# ==============================================================================
# XWorkmate Client DNS Diagnostics & Cache Self-Check Tool
# Supported OS: macOS / Linux
# ==============================================================================

set -uo pipefail

if [[ -t 1 ]]; then
  C_RESET="\033[0m"
  C_BOLD="\033[1m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_CYAN="\033[36m"
else
  C_RESET=""
  C_BOLD=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

DEFAULT_DOMAINS=(
  "xworkmate-bridge.svc.plus"
  "accounts.svc.plus"
  "openclaw.svc.plus"
)

UPSTREAM_DNS="8.8.8.8"
VERBOSE=false
DOMAINS=()

show_help() {
  cat <<EOF
${C_BOLD}用法:${C_RESET}
  $0 [选项] [域名1 域名2 ...]

${C_BOLD}说明:${C_RESET}
  诊断客户端系统的 DNS 解析机制、缓存服务状态，并检测是否存在“本地负缓存 (Negative Cache)”
  阻断、DNS 劫持、分流或解析不一致问题。

${C_BOLD}选项:${C_RESET}
  -s, --server <ip>   指定对比的上游公共 DNS 服务器 (默认: 8.8.8.8)
  -v, --verbose       显示详细调试日志
  -h, --help          显示此帮助信息

${C_BOLD}默认检查域名:${C_RESET}
  ${DEFAULT_DOMAINS[*]}

${C_BOLD}示例:${C_RESET}
  $0
  $0 xworkmate-bridge.svc.plus
  $0 -s 1.1.1.1 accounts.svc.plus
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -s|--server)
      UPSTREAM_DNS="$2"
      shift 2
      ;;
    -*)
      echo -e "${C_RED}[错误] 未知参数: $1${C_RESET}"
      show_help
      exit 1
      ;;
    *)
      DOMAINS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
  DOMAINS=("${DEFAULT_DOMAINS[@]}")
fi

OS_TYPE="$(uname -s)"
ARCH="$(uname -m)"

echo -e "${C_BOLD}${C_CYAN}=============================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}          XWorkmate 客户端 DNS 缓存自查与诊断工具             ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}=============================================================${C_RESET}"
echo -e "${C_BOLD}操作系统:${C_RESET} $OS_TYPE ($ARCH)"
echo -e "${C_BOLD}测试时间:${C_RESET} $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_BOLD}参考公共 DNS:${C_RESET} $UPSTREAM_DNS"
echo ""

# ------------------------------------------------------------------------------
# 1. 检测系统 DNS 缓存服务与网络接口
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}--- [1/3] 系统 DNS 缓存服务与网络环境自查 ---${C_RESET}"

ACTIVE_DNS_SERVERS=""
CACHE_SERVICE_DESC="未检测到活跃的系统级 DNS 缓存守护进程"

if [[ "$OS_TYPE" == "Darwin" ]]; then
  MDNS_PID="$(pgrep -x mDNSResponder 2>/dev/null || true)"
  if [[ -n "$MDNS_PID" ]]; then
    CACHE_SERVICE_DESC="macOS mDNSResponder (PID: $MDNS_PID)"
    echo -e "  • 缓存服务: ${C_GREEN}${CACHE_SERVICE_DESC}${C_RESET}"
  else
    echo -e "  • 缓存服务: ${C_YELLOW}mDNSResponder 未运行${C_RESET}"
  fi

  TUN_IF="$(ifconfig 2>/dev/null | grep -E '^(utun|ppp)' | awk -F: '{print $1}' | tr '\n' ' ' || true)"
  if [[ -n "$TUN_IF" ]]; then
    echo -e "  • 活跃隧道/VPN 接口: ${C_CYAN}${TUN_IF}${C_RESET}"
  else
    echo -e "  • 活跃隧道/VPN 接口: 无"
  fi

  ACTIVE_DNS_SERVERS="$(scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/ {print $3}' | sort -u | tr '\n' ' ' || true)"
  echo -e "  • 系统已配置的 DNS: ${ACTIVE_DNS_SERVERS:-默认网关}"

elif [[ "$OS_TYPE" == "Linux" ]]; then
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    CACHE_SERVICE_DESC="systemd-resolved"
    echo -e "  • 缓存服务: ${C_GREEN}systemd-resolved (Active)${C_RESET}"
  elif systemctl is-active --quiet dnsmasq 2>/dev/null || pgrep -x dnsmasq >/dev/null 2>&1; then
    CACHE_SERVICE_DESC="dnsmasq"
    echo -e "  • 缓存服务: ${C_GREEN}dnsmasq (Active)${C_RESET}"
  elif systemctl is-active --quiet nscd 2>/dev/null || pgrep -x nscd >/dev/null 2>&1; then
    CACHE_SERVICE_DESC="nscd"
    echo -e "  • 缓存服务: ${C_GREEN}nscd (Active)${C_RESET}"
  else
    echo -e "  • 缓存服务: ${C_YELLOW}无常驻缓存服务 (系统直连 /etc/resolv.conf)${C_RESET}"
  fi

  TUN_IF="$(ip -o link show 2>/dev/null | grep -E ':( utun| wg| tun)' | awk -F': ' '{print $2}' | tr '\n' ' ' || true)"
  if [[ -n "$TUN_IF" ]]; then
    echo -e "  • 活跃隧道/VPN 接口: ${C_CYAN}${TUN_IF}${C_RESET}"
  fi

  if [[ -f /etc/resolv.conf ]]; then
    ACTIVE_DNS_SERVERS="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | tr '\n' ' ' || true)"
    echo -e "  • /etc/resolv.conf: ${ACTIVE_DNS_SERVERS:-空}"
  fi
fi

echo ""

# ------------------------------------------------------------------------------
# 2. 核心检测逻辑函数
# ------------------------------------------------------------------------------

resolve_system() {
  local domain="$1"
  local py_out=""

  if command -v python3 >/dev/null 2>&1; then
    py_out="$(python3 -c "
import socket, sys
try:
    infos = socket.getaddrinfo('$domain', None)
    ips = sorted(list(set(info[4][0] for info in infos)))
    print('OK|' + ','.join(ips))
except Exception as e:
    print('FAIL|' + str(e))
" 2>/dev/null || true)"
    if [[ -n "$py_out" ]]; then
      echo "$py_out"
      return
    fi
  fi

  if command -v perl >/dev/null 2>&1; then
    py_out="$(perl -MSocket -e "
my @ips = ();
my @addrs = (gethostbyname('$domain'))[4];
if (@addrs) {
  for my \$a (@addrs) { push @ips, inet_ntoa(\$a); }
  print 'OK|' . join(',', @ips);
} else {
  print 'FAIL|gethostbyname failed';
}
" 2>/dev/null || true)"
    if [[ -n "$py_out" ]]; then
      echo "$py_out"
      return
    fi
  fi

  local ping_ip=""
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    ping_ip="$(ping -c 1 -W 1 "$domain" 2>&1 | awk -F'[()]' '/PING / {print $2}' || true)"
  else
    ping_ip="$(ping -c 1 -w 1 "$domain" 2>&1 | awk -F'[()]' '/PING / {print $2}' || true)"
  fi

  if [[ -n "$ping_ip" ]]; then
    echo "OK|$ping_ip"
  else
    echo "FAIL|host not found or unresolvable"
  fi
}

resolve_direct_a() {
  local domain="$1"
  local server="${2:-}"
  local res=""

  if command -v dig >/dev/null 2>&1; then
    if [[ -n "$server" ]]; then
      res="$(dig @"$server" "$domain" A +short 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ',' | sed 's/,$//' || true)"
    else
      res="$(dig "$domain" A +short 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ',' | sed 's/,$//' || true)"
    fi
  elif command -v nslookup >/dev/null 2>&1; then
    if [[ -n "$server" ]]; then
      res="$(nslookup "$domain" "$server" 2>/dev/null | awk '/^Address: / {print $2}' | grep -v '#' | tr '\n' ',' | sed 's/,$//' || true)"
    else
      res="$(nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | grep -v '#' | tr '\n' ',' | sed 's/,$//' || true)"
    fi
  fi

  echo "$res"
}

resolve_cname() {
  local domain="$1"
  local server="${2:-}"
  local res=""

  if command -v dig >/dev/null 2>&1; then
    if [[ -n "$server" ]]; then
      res="$(dig @"$server" "$domain" CNAME +short 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
    else
      res="$(dig "$domain" CNAME +short 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
    fi
  fi

  echo "$res"
}

# ------------------------------------------------------------------------------
# 3. 逐个域名诊断
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}--- [2/3] 域名解析与缓存健康状态诊断 ---${C_RESET}"

HAS_NEGATIVE_CACHE=false
HAS_ANOMALY=false

for d in "${DOMAINS[@]}"; do
  echo -e "\n${C_BOLD}🔍 正在检查: ${C_CYAN}${d}${C_RESET}"

  SYS_RESULT="$(resolve_system "$d")"
  SYS_STATUS="$(echo "$SYS_RESULT" | cut -d'|' -f1)"
  SYS_DATA="$(echo "$SYS_RESULT" | cut -d'|' -f2-)"

  UPSTREAM_IPS="$(resolve_direct_a "$d" "$UPSTREAM_DNS")"
  UPSTREAM_CNAME="$(resolve_cname "$d" "$UPSTREAM_DNS")"

  LOCAL_DNS_IPS="$(resolve_direct_a "$d")"
  LOCAL_CNAME="$(resolve_cname "$d")"

  if $VERBOSE; then
    echo "  [Debug] SYS_RESULT: $SYS_RESULT"
    echo "  [Debug] LOCAL_DNS_IPS: $LOCAL_DNS_IPS, LOCAL_CNAME: $LOCAL_CNAME"
    echo "  [Debug] UPSTREAM_IPS: $UPSTREAM_IPS, UPSTREAM_CNAME: $UPSTREAM_CNAME"
  fi

  echo -e "  • 系统底层解析 (getaddrinfo): $([[ "$SYS_STATUS" == "OK" ]] && echo -e "${C_GREEN}${SYS_DATA}${C_RESET}" || echo -e "${C_RED}失败 (${SYS_DATA})${C_RESET}")"
  echo -e "  • 本地 DNS (直接查询): ${LOCAL_DNS_IPS:-无A记录} $([[ -n "$LOCAL_CNAME" ]] && echo "(CNAME: $LOCAL_CNAME)")"
  echo -e "  • 公共 DNS ($UPSTREAM_DNS): ${UPSTREAM_IPS:-无A记录} $([[ -n "$UPSTREAM_CNAME" ]] && echo "(CNAME: $UPSTREAM_CNAME)")"

  if [[ "$SYS_STATUS" == "FAIL" && -n "$UPSTREAM_IPS" ]]; then
    echo -e "  ${C_BOLD}${C_RED}❌ [异常: 本地负缓存阻断 / Negative Cache Detected]${C_RESET}"
    echo -e "     ${C_RED}上游公共 DNS 能正常解析为 [$UPSTREAM_IPS]，但客户端系统底层解析失败！${C_RESET}"
    echo -e "     原因: 系统 DNS 缓存中存有旧的 NXDOMAIN 或失败记录，正在阻止连接。"
    echo -e "     建议: 立即执行清理命令: ${C_BOLD}sudo ./scripts/dns-flush.sh${C_RESET}"
    HAS_NEGATIVE_CACHE=true
    HAS_ANOMALY=true

  elif [[ "$SYS_STATUS" == "FAIL" && -z "$UPSTREAM_IPS" ]]; then
    echo -e "  ${C_BOLD}${C_RED}❌ [异常: 域名完全不可解析 / Unresolvable]${C_RESET}"
    echo -e "     系统与上游公共 DNS 均未能解析该域名。请核对域名拼写或 Cloudflare DNS 配置。"
    HAS_ANOMALY=true

  elif [[ "$SYS_STATUS" == "OK" ]]; then
    if [[ -n "$LOCAL_CNAME" && -n "$LOCAL_DNS_IPS" ]]; then
      echo -e "  ${C_BLUE}ℹ️  [提示: CNAME 扁平化生效]${C_RESET} 存在 CNAME 指向 [$LOCAL_CNAME]，已扁平化直接返回 A 记录。"
    fi

    if [[ -n "$UPSTREAM_IPS" && "$SYS_DATA" != *"$UPSTREAM_IPS"* ]]; then
      echo -e "  ${C_YELLOW}⚠️  [提示: 解析分流 / IP 不一致]${C_RESET} 系统解析出的 IP ($SYS_DATA) 与公网 DNS ($UPSTREAM_IPS) 不一致。"
      echo -e "     说明: 可能处于 VPN、自建代理网关或分流规则 (Clash/Surge/utun) 下，若业务正常可忽略。"
    else
      echo -e "  ${C_GREEN}✅ [正常: 解析一致且健康]${C_RESET} 系统底层与上游 DNS 均可正常解析访问。"
    fi
  fi
done

echo ""
# ------------------------------------------------------------------------------
# 4. 总结与行动指南
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}--- [3/3] 诊断总结与操作建议 ---${C_RESET}"

if $HAS_NEGATIVE_CACHE; then
  echo -e "${C_BOLD}${C_RED}检测到明确的 DNS 负缓存异常！客户端连接可能受阻。${C_RESET}"
  echo -e "请执行以下清理脚本以刷新系统缓存:"
  echo -e "  ${C_BOLD}${C_GREEN}sudo ./scripts/dns-flush.sh${C_RESET}"
  exit 2
elif $HAS_ANOMALY; then
  echo -e "${C_BOLD}${C_YELLOW}检测到部分域名解析异常，请根据上述提示排查网络或 DNS 配置。${C_RESET}"
  exit 1
else
  echo -e "${C_BOLD}${C_GREEN}🎉 所有待检测域名的 DNS 状态均正常，未发现本地负缓存残留。${C_RESET}"
  exit 0
fi
