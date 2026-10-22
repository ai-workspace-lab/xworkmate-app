#!/usr/bin/env bash
# ==============================================================================
# XWorkmate Client DNS Cache Flush & Reset Tool
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

AUTO_VERIFY=true
VERIFY_DOMAINS=()

show_help() {
  cat <<EOF
${C_BOLD}用法:${C_RESET}
  sudo $0 [选项] [域名1 域名2 ...]

${C_BOLD}说明:${C_RESET}
  一键清理当前操作系统的本地 DNS 解析缓存与负缓存 (Negative Cache)，并在清理后自动
  自查域名解析恢复情况。

${C_BOLD}选项:${C_RESET}
  --no-verify         清理完成后不执行自动验证
  -h, --help          显示此帮助信息

${C_BOLD}示例:${C_RESET}
  sudo $0
  sudo $0 --no-verify
  sudo $0 xworkmate-bridge.svc.plus
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --no-verify)
      AUTO_VERIFY=false
      shift
      ;;
    -*)
      echo -e "${C_RED}[错误] 未知参数: $1${C_RESET}"
      show_help
      exit 1
      ;;
    *)
      VERIFY_DOMAINS+=("$1")
      shift
      ;;
  esac
done

OS_TYPE="$(uname -s)"

echo -e "${C_BOLD}${C_CYAN}=============================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}            XWorkmate 客户端 DNS 缓存清理工具                  ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}=============================================================${C_RESET}"

# 权限检测与自动提权
if [[ $EUID -ne 0 ]]; then
  echo -e "${C_YELLOW}当前操作需要系统管理员权限 (root/sudo) 来清理系统缓存守护进程。${C_RESET}"
  if command -v sudo >/dev/null 2>&1; then
    echo -e "正在尝试通过 sudo 提权..."
    exec sudo "$0" "$@"
  else
    echo -e "${C_RED}[错误] 未找到 sudo，请以 root 用户重新执行此脚本。${C_RESET}"
    exit 1
  fi
fi

FLUSHED=false

# ------------------------------------------------------------------------------
# macOS 清理逻辑
# ------------------------------------------------------------------------------
if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo -e "\n${C_BOLD}正在清理 macOS DNS 缓存...${C_RESET}"

  if dscacheutil -flushcache 2>/dev/null; then
    echo -e "  • ${C_GREEN}✓${C_RESET} dscacheutil -flushcache 成功"
  else
    echo -e "  • ${C_YELLOW}!${C_RESET} dscacheutil -flushcache 执行异常 (忽略)"
  fi

  if killall -HUP mDNSResponder 2>/dev/null; then
    echo -e "  • ${C_GREEN}✓${C_RESET} killall -HUP mDNSResponder (mDNSResponder 缓存已重置)"
    FLUSHED=true
  else
    echo -e "  • ${C_YELLOW}!${C_RESET} 未能发送 HUP 信号给 mDNSResponder，尝试 launchctl kickstart..."
    if launchctl kickstart -k system/com.apple.networking.discoveryutil 2>/dev/null || \
       launchctl kickstart -k system/com.apple.mDNSResponder 2>/dev/null; then
      echo -e "  • ${C_GREEN}✓${C_RESET} launchctl kickstart mDNSResponder 成功"
      FLUSHED=true
    fi
  fi

# ------------------------------------------------------------------------------
# Linux 清理逻辑
# ------------------------------------------------------------------------------
elif [[ "$OS_TYPE" == "Linux" ]]; then
  echo -e "\n${C_BOLD}正在清理 Linux DNS 缓存...${C_RESET}"

  if command -v resolvectl >/dev/null 2>&1; then
    if resolvectl flush-caches 2>/dev/null; then
      echo -e "  • ${C_GREEN}✓${C_RESET} resolvectl flush-caches 成功"
      FLUSHED=true
    fi
  elif command -v systemd-resolve >/dev/null 2>&1; then
    if systemd-resolve --flush-caches 2>/dev/null; then
      echo -e "  • ${C_GREEN}✓${C_RESET} systemd-resolve --flush-caches 成功"
      FLUSHED=true
    fi
  fi

  if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    systemctl restart dnsmasq
    echo -e "  • ${C_GREEN}✓${C_RESET} 重启 dnsmasq 服务成功"
    FLUSHED=true
  elif service dnsmasq status >/dev/null 2>&1; then
    service dnsmasq restart >/dev/null 2>&1 || true
    echo -e "  • ${C_GREEN}✓${C_RESET} 重启 dnsmasq (service) 成功"
    FLUSHED=true
  fi

  if command -v nscd >/dev/null 2>&1; then
    nscd -i hosts >/dev/null 2>&1 || true
    echo -e "  • ${C_GREEN}✓${C_RESET} nscd hosts 缓存已清空"
    FLUSHED=true
  fi

  if command -v rndc >/dev/null 2>&1; then
    rndc flush >/dev/null 2>&1 || true
    echo -e "  • ${C_GREEN}✓${C_RESET} rndc flush 成功"
    FLUSHED=true
  fi

  if ! $FLUSHED; then
    echo -e "  • ${C_BLUE}ℹ️  当前 Linux 系统未运行常驻 DNS 缓存服务 (直连 /etc/resolv.conf)，无需清理。${C_RESET}"
    FLUSHED=true
  fi

else
  echo -e "${C_RED}[错误] 不支持的操作系统: $OS_TYPE${C_RESET}"
  exit 1
fi

if $FLUSHED; then
  echo -e "\n${C_BOLD}${C_GREEN}🎉 本地 DNS 缓存已成功清理完成！${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 自动自查与验证
# ------------------------------------------------------------------------------
if $AUTO_VERIFY; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CHECK_SCRIPT="$SCRIPT_DIR/dns-check.sh"

  if [[ -f "$CHECK_SCRIPT" ]]; then
    echo -e "\n${C_BOLD}--- 立即执行解析自查验证 ---${C_RESET}"
    if [[ ${#VERIFY_DOMAINS[@]} -gt 0 ]]; then
      bash "$CHECK_SCRIPT" "${VERIFY_DOMAINS[@]}"
    else
      bash "$CHECK_SCRIPT"
    fi
  fi
fi
