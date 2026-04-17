#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a && source ./.env && set +a
fi

SSH_TARGET="${XWORKMATE_TEST_SSH_TARGET:-root@xworkmate-bridge.svc.plus}"
BRIDGE_SERVICE="${XWORKMATE_TEST_BRIDGE_SERVICE:-xworkmate-bridge.svc.plus}"
CADDY_CONFIG="${XWORKMATE_TEST_CADDY_CONFIG:-/etc/caddy/conf.d/xworkmate-bridge.caddy}"
SSH_BIN="${SSH_BIN:-ssh}"
SSH_CONNECT_TIMEOUT="${XWORKMATE_TEST_SSH_CONNECT_TIMEOUT:-8}"
SSH_EXTRA_OPTS="${XWORKMATE_TEST_SSH_OPTS:-}"
JOURNAL_LINES="${XWORKMATE_TEST_BRIDGE_JOURNAL_LINES:-80}"

echo "==> Inspecting ${BRIDGE_SERVICE} on ${SSH_TARGET}"

# shellcheck disable=SC2086
"${SSH_BIN}" \
  -o BatchMode=yes \
  -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}" \
  ${SSH_EXTRA_OPTS} \
  "${SSH_TARGET}" bash -s -- "${BRIDGE_SERVICE}" "${JOURNAL_LINES}" "${CADDY_CONFIG}" <<'REMOTE'
set -euo pipefail

service_name="${1}"
journal_lines="${2}"
caddy_config="${3}"

echo "## Access"
echo "host=$(hostname -f 2>/dev/null || hostname)"
echo "time=$(date -Is)"
echo "kernel=$(uname -srmo)"
echo

echo "## Caddy Configuration"
if [[ -f "${caddy_config}" ]]; then
  echo "path: ${caddy_config}"
  cat "${caddy_config}"
else
  echo "Caddy config not found at ${caddy_config}"
fi
echo

echo "## System"
systemctl is-system-running || true
echo

echo "## Service Summary"
systemctl show "${service_name}" \
  --property=Id \
  --property=Description \
  --property=LoadState \
  --property=ActiveState \
  --property=SubState \
  --property=UnitFileState \
  --property=FragmentPath \
  --property=ExecMainPID \
  --property=ExecMainStartTimestamp \
  --property=MemoryCurrent \
  --property=TasksCurrent \
  --property=User \
  --property=Group || true
echo

echo "## Service Status"
systemctl status "${service_name}" --no-pager --full || true
echo

echo "## Recent Journal"
journalctl -u "${service_name}" -n "${journal_lines}" --no-pager || true
echo

echo "## Listening Ports"
ss -ltnp | grep -E 'LISTEN|4317|4318|8080|8787|18789' || true
echo

echo "## Process Snapshot"
main_pid="$(systemctl show "${service_name}" --property=ExecMainPID --value 2>/dev/null || true)"
if [[ -n "${main_pid}" && "${main_pid}" != "0" ]]; then
  ps -p "${main_pid}" -o pid,ppid,user,%cpu,%mem,etime,command || true
else
  echo "main process not running"
fi
REMOTE
