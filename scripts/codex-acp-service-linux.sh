#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./codex-acp-service-common.sh
source "$SCRIPT_DIR/codex-acp-service-common.sh"

SERVICE_NAME="${XWORKMATE_CODEX_ACP_SERVICE_NAME:-xworkmate-codex-acp.service}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SYSTEMD_USER_DIR="${XWORKMATE_CODEX_ACP_SYSTEMD_USER_DIR:-$XDG_CONFIG_HOME/systemd/user}"
CONFIG_DIR="${XWORKMATE_CODEX_ACP_CONFIG_DIR:-$XDG_CONFIG_HOME/xworkmate/codex-acp}"
RUNTIME_DIR="${XWORKMATE_CODEX_ACP_RUNTIME_DIR:-$XDG_STATE_HOME/xworkmate/codex-acp}"
LOG_DIR=""
CONFIG_FILE="$CONFIG_DIR/config.env"
LAUNCHER_FILE="$RUNTIME_DIR/run-codex-acp.sh"
SERVICE_FILE="$SYSTEMD_USER_DIR/$SERVICE_NAME"

linux_has_systemctl() {
  command -v systemctl >/dev/null 2>&1
}

linux_require_systemctl() {
  if [[ "$XWORKMATE_CODEX_ACP_DRY_RUN" == "1" ]]; then
    return 0
  fi
  linux_has_systemctl || common_die "systemctl is required for Linux native service control."
}

linux_usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [--port PORT] [--lines N]

Commands:
  install         Write user unit + enable/start Codex ACP service
  start           Start service using configured or auto-selected port
  stop            Stop the user service
  restart         Restart service, re-picking a free port if needed
  status          Show service state and endpoint
  endpoint        Print configured websocket endpoint
  logs            Show recent journal lines
  set-port PORT   Reconfigure the service port, then restart if active
  uninstall       Stop service and remove systemd user unit + generated files
  help            Show this message

Defaults:
  host            $XWORKMATE_CODEX_ACP_DEFAULT_HOST
  default port    $XWORKMATE_CODEX_ACP_DEFAULT_PORT

Environment:
  CODEX_BIN=/absolute/path/to/codex
  XWORKMATE_CODEX_ACP_DRY_RUN=1    Generate files without calling systemctl
EOF
}

linux_is_active() {
  if ! linux_has_systemctl; then
    return 1
  fi
  systemctl --user is-active --quiet "$SERVICE_NAME"
}

linux_state() {
  if ! linux_has_systemctl; then
    printf 'unavailable (systemctl missing)\n'
    return 0
  fi

  if systemctl --user is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
    if linux_is_active; then
      printf 'active\n'
      return 0
    fi
    printf 'enabled\n'
    return 0
  fi
  if linux_is_active; then
    printf 'active\n'
    return 0
  fi
  printf 'inactive\n'
}

linux_write_service_file() {
  common_ensure_dirs
  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=XWorkmate Codex ACP app-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$LAUNCHER_FILE
Restart=on-failure
RestartSec=2
WorkingDirectory=$HOME
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
}

linux_prepare_service() {
  common_load_config

  local configured_port="${CODEX_ACP_PORT:-$XWORKMATE_CODEX_ACP_DEFAULT_PORT}"
  local requested_port="${PORT_OVERRIDE:-$configured_port}"
  local preserve_busy="0"
  if linux_is_active && [[ "$requested_port" == "$configured_port" ]]; then
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
  linux_write_service_file
}

linux_reload_units() {
  linux_require_systemctl
  common_run_service_cmd systemctl --user daemon-reload
}

linux_activate_service() {
  linux_reload_units
  common_run_service_cmd systemctl --user enable --now "$SERVICE_NAME"
}

linux_stop_service() {
  linux_require_systemctl
  if ! linux_is_active; then
    common_info "Service is not active."
    return 0
  fi
  common_run_service_cmd systemctl --user stop "$SERVICE_NAME"
}

linux_status() {
  common_info "platform: Linux"
  common_info "service: $SERVICE_NAME"
  common_info "state: $(linux_state)"
  common_info "endpoint: $(common_endpoint_from_config)"
  common_info "unit: $SERVICE_FILE"
  common_info "config: $CONFIG_FILE"
}

linux_logs() {
  linux_require_systemctl
  common_run_service_cmd journalctl --user -u "$SERVICE_NAME" -n "$LOG_LINES" --no-pager
}

linux_uninstall() {
  linux_require_systemctl
  common_run_service_cmd_allow_fail systemctl --user disable --now "$SERVICE_NAME"
  rm -f "$SERVICE_FILE" "$LAUNCHER_FILE" "$CONFIG_FILE"
  linux_reload_units
  common_cleanup_dir_if_empty "$RUNTIME_DIR"
  common_cleanup_dir_if_empty "$CONFIG_DIR"
  common_info "Removed user unit: $SERVICE_NAME"
}

common_parse_args "$@"

case "$ACTION" in
  install)
    linux_prepare_service
    linux_activate_service
    common_info "Codex ACP service ready at $(common_endpoint_from_config)"
    ;;
  start)
    if linux_is_active && [[ -z "$PORT_OVERRIDE" ]]; then
      common_info "Service already active at $(common_endpoint_from_config)"
      exit 0
    fi
    linux_prepare_service
    linux_activate_service
    common_info "Codex ACP service started at $(common_endpoint_from_config)"
    ;;
  stop)
    linux_stop_service
    ;;
  restart)
    linux_prepare_service
    linux_reload_units
    if linux_is_active; then
      common_run_service_cmd systemctl --user restart "$SERVICE_NAME"
    else
      common_run_service_cmd systemctl --user start "$SERVICE_NAME"
    fi
    common_info "Codex ACP service restarted at $(common_endpoint_from_config)"
    ;;
  status)
    linux_status
    ;;
  endpoint)
    common_endpoint_from_config
    ;;
  logs)
    linux_logs
    ;;
  set-port)
    [[ -n "$PORT_OVERRIDE" ]] || common_die "set-port requires a port value"
    linux_prepare_service
    linux_reload_units
    if linux_is_active; then
      common_run_service_cmd systemctl --user restart "$SERVICE_NAME"
      common_info "Codex ACP service moved to $(common_endpoint_from_config)"
    else
      common_info "Configured Codex ACP service for $(common_endpoint_from_config)"
    fi
    ;;
  uninstall)
    linux_uninstall
    ;;
  help)
    linux_usage
    ;;
  *)
    common_die "Unknown command: $ACTION"
    ;;
esac
