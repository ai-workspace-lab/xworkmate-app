#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./codex-acp-service-common.sh
source "$SCRIPT_DIR/codex-acp-service-common.sh"

macos_launchctl_domain() {
  if launchctl print "gui/$UID" >/dev/null 2>&1; then
    printf 'gui/%s\n' "$UID"
    return 0
  fi
  printf 'user/%s\n' "$UID"
}

SERVICE_LABEL="${XWORKMATE_CODEX_ACP_SERVICE_LABEL:-plus.svc.xworkmate.codex-acp}"
CONFIG_DIR="${XWORKMATE_CODEX_ACP_CONFIG_DIR:-$HOME/Library/Application Support/XWorkmate/codex-acp}"
RUNTIME_DIR="${XWORKMATE_CODEX_ACP_RUNTIME_DIR:-$CONFIG_DIR/runtime}"
LOG_DIR="${XWORKMATE_CODEX_ACP_LOG_DIR:-$HOME/Library/Logs/XWorkmate/codex-acp}"
CONFIG_FILE="$CONFIG_DIR/config.env"
LAUNCHER_FILE="$RUNTIME_DIR/run-codex-acp.sh"
PLIST_DIR="${XWORKMATE_CODEX_ACP_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
SERVICE_FILE="$PLIST_DIR/$SERVICE_LABEL.plist"
LAUNCHCTL_DOMAIN="${XWORKMATE_CODEX_ACP_LAUNCHCTL_DOMAIN:-$(macos_launchctl_domain)}"

macos_usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [--port PORT] [--lines N]

Commands:
  install         Write LaunchAgent + start Codex ACP service
  start           Start service using configured or auto-selected port
  stop            Stop the LaunchAgent
  restart         Restart service, re-picking a free port if needed
  status          Show service state and endpoint
  endpoint        Print configured websocket endpoint
  logs            Tail saved stdout/stderr logs
  set-port PORT   Reconfigure the service port, then restart if loaded
  uninstall       Stop service and remove LaunchAgent + generated files
  help            Show this message

Defaults:
  host            $XWORKMATE_CODEX_ACP_DEFAULT_HOST
  default port    $XWORKMATE_CODEX_ACP_DEFAULT_PORT
  launchctl       $LAUNCHCTL_DOMAIN

Environment:
  CODEX_BIN=/absolute/path/to/codex
  XWORKMATE_CODEX_ACP_DRY_RUN=1    Generate files without calling launchctl
EOF
}

macos_is_loaded() {
  launchctl print "$LAUNCHCTL_DOMAIN/$SERVICE_LABEL" >/dev/null 2>&1
}

macos_state() {
  if ! macos_is_loaded; then
    printf 'unloaded\n'
    return 0
  fi

  local state
  state="$(launchctl print "$LAUNCHCTL_DOMAIN/$SERVICE_LABEL" 2>/dev/null | awk -F'= ' '/state =/ { print $2; exit }')"
  if [[ -n "$state" ]]; then
    printf '%s\n' "$state"
    return 0
  fi
  printf 'loaded\n'
}

macos_write_service_file() {
  common_ensure_dirs
  mkdir -p "$PLIST_DIR"

  cat > "$SERVICE_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$SERVICE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$LAUNCHER_FILE</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$PATH</string>
  </dict>
</dict>
</plist>
EOF
}

macos_prepare_service() {
  common_load_config

  local configured_port="${CODEX_ACP_PORT:-$XWORKMATE_CODEX_ACP_DEFAULT_PORT}"
  local requested_port="${PORT_OVERRIDE:-$configured_port}"
  local preserve_busy="0"
  if macos_is_loaded && [[ "$requested_port" == "$configured_port" ]]; then
    preserve_busy="1"
  fi

  local codex_bin="${CODEX_BIN:-}"
  if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
    codex_bin="$(common_resolve_codex_bin)"
  fi

  local selected_port
  selected_port="$(common_select_port "$requested_port" "$configured_port" "$preserve_busy")"
  if [[ "$selected_port" != "$requested_port" ]]; then
    common_warn "Port $requested_port is busy; using $selected_port instead."
  fi

  local listen_url
  listen_url="$(common_listen_url "$selected_port")"

  common_write_config "$codex_bin" "$selected_port"
  common_write_launcher "$codex_bin" "$listen_url"
  macos_write_service_file
}

macos_activate_service() {
  common_run_service_cmd_allow_fail launchctl bootout "$LAUNCHCTL_DOMAIN" "$SERVICE_FILE"
  common_run_service_cmd launchctl bootstrap "$LAUNCHCTL_DOMAIN" "$SERVICE_FILE"
  common_run_service_cmd launchctl kickstart -k "$LAUNCHCTL_DOMAIN/$SERVICE_LABEL"
}

macos_stop_service() {
  if ! macos_is_loaded; then
    common_info "Service is not loaded."
    return 0
  fi
  common_run_service_cmd launchctl bootout "$LAUNCHCTL_DOMAIN" "$SERVICE_FILE"
}

macos_status() {
  common_info "platform: macOS"
  common_info "label: $SERVICE_LABEL"
  common_info "state: $(macos_state)"
  common_info "endpoint: $(common_endpoint_from_config)"
  common_info "launch agent: $SERVICE_FILE"
  common_info "config: $CONFIG_FILE"
  common_info "logs:"
  common_info "  $LOG_DIR/stdout.log"
  common_info "  $LOG_DIR/stderr.log"
}

macos_logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR/stdout.log" "$LOG_DIR/stderr.log"
  common_info "==> $LOG_DIR/stdout.log <=="
  tail -n "$LOG_LINES" "$LOG_DIR/stdout.log"
  common_info
  common_info "==> $LOG_DIR/stderr.log <=="
  tail -n "$LOG_LINES" "$LOG_DIR/stderr.log"
}

macos_uninstall() {
  macos_stop_service
  rm -f "$SERVICE_FILE" "$LAUNCHER_FILE" "$CONFIG_FILE"
  common_cleanup_dir_if_empty "$RUNTIME_DIR"
  common_cleanup_dir_if_empty "$CONFIG_DIR"
  common_info "Removed LaunchAgent: $SERVICE_LABEL"
}

common_parse_args "$@"

case "$ACTION" in
  install)
    macos_prepare_service
    macos_activate_service
    common_info "Codex ACP service ready at $(common_endpoint_from_config)"
    ;;
  start)
    if macos_is_loaded && [[ -z "$PORT_OVERRIDE" ]]; then
      common_info "Service already loaded at $(common_endpoint_from_config)"
      exit 0
    fi
    macos_prepare_service
    macos_activate_service
    common_info "Codex ACP service started at $(common_endpoint_from_config)"
    ;;
  stop)
    macos_stop_service
    ;;
  restart)
    macos_prepare_service
    macos_activate_service
    common_info "Codex ACP service restarted at $(common_endpoint_from_config)"
    ;;
  status)
    macos_status
    ;;
  endpoint)
    common_endpoint_from_config
    ;;
  logs)
    macos_logs
    ;;
  set-port)
    [[ -n "$PORT_OVERRIDE" ]] || common_die "set-port requires a port value"
    macos_prepare_service
    if macos_is_loaded; then
      macos_activate_service
      common_info "Codex ACP service moved to $(common_endpoint_from_config)"
    else
      common_info "Configured Codex ACP service for $(common_endpoint_from_config)"
    fi
    ;;
  uninstall)
    macos_uninstall
    ;;
  help)
    macos_usage
    ;;
  *)
    common_die "Unknown command: $ACTION"
    ;;
esac
