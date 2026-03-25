#!/usr/bin/env bash
set -euo pipefail

XWORKMATE_CODEX_ACP_DEFAULT_HOST="${XWORKMATE_CODEX_ACP_DEFAULT_HOST:-127.0.0.1}"
XWORKMATE_CODEX_ACP_DEFAULT_PORT="${XWORKMATE_CODEX_ACP_DEFAULT_PORT:-9001}"
XWORKMATE_CODEX_ACP_PORT_SCAN_LIMIT="${XWORKMATE_CODEX_ACP_PORT_SCAN_LIMIT:-100}"
XWORKMATE_CODEX_ACP_DRY_RUN="${XWORKMATE_CODEX_ACP_DRY_RUN:-0}"

common_die() {
  echo "Error: $*" >&2
  exit 1
}

common_info() {
  echo "$*"
}

common_warn() {
  echo "Warning: $*" >&2
}

common_print_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

common_run_service_cmd() {
  if [[ "$XWORKMATE_CODEX_ACP_DRY_RUN" == "1" ]]; then
    common_print_cmd "$@"
    return 0
  fi
  "$@"
}

common_run_service_cmd_allow_fail() {
  if [[ "$XWORKMATE_CODEX_ACP_DRY_RUN" == "1" ]]; then
    common_print_cmd "$@"
    return 0
  fi
  "$@" || true
}

common_validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    common_die "Invalid port: $port"
  fi
  if (( port < 1 || port > 65535 )); then
    common_die "Port out of range: $port"
  fi
}

common_resolve_codex_bin() {
  local candidate="${CODEX_BIN:-${XWORKMATE_CODEX_ACP_CODEX_BIN:-}}"
  if [[ -z "$candidate" ]]; then
    candidate="$(command -v codex || true)"
  fi
  if [[ -z "$candidate" ]]; then
    common_die "Unable to find codex in PATH. Set CODEX_BIN=/absolute/path/to/codex."
  fi
  if [[ ! -x "$candidate" ]]; then
    common_die "codex binary is not executable: $candidate"
  fi
  printf '%s\n' "$candidate"
}

common_listen_url() {
  local port="$1"
  printf 'ws://%s:%s\n' "$XWORKMATE_CODEX_ACP_DEFAULT_HOST" "$port"
}

common_load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

common_ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$RUNTIME_DIR"
  if [[ -n "${LOG_DIR:-}" ]]; then
    mkdir -p "$LOG_DIR"
  fi
}

common_write_config() {
  local codex_bin="$1"
  local port="$2"
  local listen_url
  listen_url="$(common_listen_url "$port")"

  common_ensure_dirs

  {
    printf 'CODEX_BIN=%q\n' "$codex_bin"
    printf 'CODEX_ACP_HOST=%q\n' "$XWORKMATE_CODEX_ACP_DEFAULT_HOST"
    printf 'CODEX_ACP_PORT=%q\n' "$port"
    printf 'CODEX_ACP_LISTEN_URL=%q\n' "$listen_url"
  } > "$CONFIG_FILE"
}

common_write_launcher() {
  local codex_bin="$1"
  local listen_url="$2"

  common_ensure_dirs

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'exec '
    printf '%q ' "$codex_bin" "app-server" "--listen" "$listen_url"
    printf '\n'
  } > "$LAUNCHER_FILE"

  chmod +x "$LAUNCHER_FILE"
}

common_port_is_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn 2>/dev/null | awk -v needle=":$port" '
      $4 ~ needle "$" { found = 1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | awk -v needle=":$port" '
      $1 ~ /^tcp/ && $4 ~ needle "$" && $NF ~ /LISTEN|LISTENING/ { found = 1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z "$XWORKMATE_CODEX_ACP_DEFAULT_HOST" "$port" >/dev/null 2>&1
    return $?
  fi

  common_die "Unable to detect port availability. Install one of lsof, ss, netstat, or nc."
}

common_find_available_port() {
  local preferred="$1"
  local port
  local max_port=$((preferred + XWORKMATE_CODEX_ACP_PORT_SCAN_LIMIT))

  if (( max_port > 65535 )); then
    max_port=65535
  fi

  for ((port = preferred; port <= max_port; port++)); do
    if ! common_port_is_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  common_die "No free port found in range ${preferred}-${max_port}."
}

common_select_port() {
  local preferred="$1"
  local current_port="${2:-}"
  local preserve_current_busy="${3:-0}"

  common_validate_port "$preferred"

  if [[ "$preserve_current_busy" == "1" && -n "$current_port" && "$preferred" == "$current_port" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi

  if common_port_is_in_use "$preferred"; then
    common_find_available_port "$preferred"
    return 0
  fi

  printf '%s\n' "$preferred"
}

common_endpoint_from_config() {
  common_load_config
  local port="${CODEX_ACP_PORT:-$XWORKMATE_CODEX_ACP_DEFAULT_PORT}"
  common_validate_port "$port"
  common_listen_url "$port"
}

common_cleanup_dir_if_empty() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    rmdir "$dir" 2>/dev/null || true
  fi
}

common_parse_args() {
  ACTION="${1:-help}"
  shift || true

  PORT_OVERRIDE=""
  LOG_LINES="50"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        shift
        [[ $# -gt 0 ]] || common_die "--port requires a value"
        PORT_OVERRIDE="$1"
        shift
        ;;
      --lines)
        shift
        [[ $# -gt 0 ]] || common_die "--lines requires a value"
        LOG_LINES="$1"
        shift
        ;;
      -h|--help|help)
        ACTION="help"
        shift
        ;;
      *)
        if [[ "$ACTION" == "set-port" && -z "$PORT_OVERRIDE" ]]; then
          PORT_OVERRIDE="$1"
          shift
          continue
        fi
        common_die "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -n "$PORT_OVERRIDE" ]]; then
    common_validate_port "$PORT_OVERRIDE"
  fi
  if [[ ! "$LOG_LINES" =~ ^[0-9]+$ ]]; then
    common_die "Invalid --lines value: $LOG_LINES"
  fi
}
