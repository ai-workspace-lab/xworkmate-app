#!/usr/bin/env bash
set -euo pipefail

ACCOUNTS_BASE_URL="${REVIEW_ACCOUNT_BASE_URL:-https://accounts.svc.plus}"
REVIEW_ACCOUNT_LOGIN_NAME="${REVIEW_ACCOUNT_LOGIN_NAME:-review@svc.plus}"
REVIEW_ACCOUNT_LOGIN_PASSWORD="${REVIEW_ACCOUNT_LOGIN_PASSWORD:-}"
BRIDGE_SERVER_URL="${BRIDGE_SERVER_URL:-}"
BRIDGE_AUTH_TOKEN="${BRIDGE_AUTH_TOKEN:-}"
HTTP_TIMEOUT_SECONDS="${HTTP_TIMEOUT_SECONDS:-30}"

if [[ -z "${REVIEW_ACCOUNT_LOGIN_PASSWORD}" ]]; then
  echo "REVIEW_ACCOUNT_LOGIN_PASSWORD is required" >&2
  exit 1
fi

normalize_url() {
  local raw="$1"
  raw="${raw%"${raw##*[![:space:]]}"}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  printf '%s\n' "${raw%/}"
}

json_post() {
  local url="$1"
  local data="$2"
  shift 2
  curl \
    --silent \
    --show-error \
    --fail \
    --location \
    --max-time "${HTTP_TIMEOUT_SECONDS}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    "$@" \
    --data "${data}" \
    "${url}"
}

json_get() {
  local url="$1"
  shift
  curl \
    --silent \
    --show-error \
    --fail \
    --location \
    --max-time "${HTTP_TIMEOUT_SECONDS}" \
    -H 'Accept: application/json' \
    "$@" \
    "${url}"
}

accounts_base_url="$(normalize_url "${ACCOUNTS_BASE_URL}")"

login_payload="$(python3 - <<'PY'
import json
import os
login_name = os.environ.get("REVIEW_ACCOUNT_LOGIN_NAME", "review@svc.plus")
login_password = os.environ.get("REVIEW_ACCOUNT_LOGIN_PASSWORD", "")
print(json.dumps({
    "identifier": login_name,
    "password": login_password,
}))
PY
)"

login_json="$(
  json_post \
    "${accounts_base_url}/api/auth/login" \
    "${login_payload}"
)"

session_token="$(
  RESPONSE_JSON="${login_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
token = str(payload.get("token") or payload.get("access_token") or "").strip()
if not token:
    raise SystemExit("login response did not include a usable token")
print(token)
PY
)"

session_json="$(
  json_get \
    "${accounts_base_url}/api/auth/session" \
    -H "Authorization: Bearer ${session_token}"
)"

sync_json="$(
  json_get \
    "${accounts_base_url}/api/auth/xworkmate/profile/sync" \
    -H "Authorization: Bearer ${session_token}"
)"

bridge_server_url="${BRIDGE_SERVER_URL}"
if [[ -z "${bridge_server_url}" ]]; then
  bridge_server_url="$(
    RESPONSE_JSON="${sync_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
bridge_url = str(payload.get("BRIDGE_SERVER_URL") or payload.get("bridgeServerUrl") or "").strip()
if not bridge_url:
    raise SystemExit("sync response did not include BRIDGE_SERVER_URL")
print(bridge_url.rstrip("/"))
PY
  )"
fi
bridge_server_url="$(normalize_url "${bridge_server_url}")"

bridge_auth_token="${BRIDGE_AUTH_TOKEN}"
if [[ -z "${bridge_auth_token}" ]]; then
  bridge_auth_token="$(
    RESPONSE_JSON="${sync_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
token = str(payload.get("BRIDGE_AUTH_TOKEN") or "").strip()
if not token:
    raise SystemExit("sync response did not include BRIDGE_AUTH_TOKEN")
print(token)
PY
  )"
fi

capabilities_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    '{"jsonrpc":"2.0","id":"capabilities","method":"acp.capabilities","params":{}}' \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

start_payload='{"jsonrpc":"2.0","id":"start","method":"thread/start","params":{"sessionId":"scenario-session-001","threadId":"scenario-session-001","mode":"gateway-chat","taskPrompt":"Say hello in one short sentence.","workingDirectory":"/tmp","selectedSkills":[],"attachments":[],"provider":"codex","routing":{"routingMode":"auto","preferredGatewayTarget":"codex","explicitExecutionTarget":"agent","explicitProviderId":"codex","explicitModel":"","explicitSkills":[],"allowSkillInstall":false,"availableSkills":[]},"requestedExecutionTarget":"agent","executionTarget":"agent"}}'
start_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    "${start_payload}" \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

turn_id="$(
  RESPONSE_JSON="${start_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
turn_id = str(result.get("turnId") or "").strip()
if not turn_id:
    raise SystemExit("thread/start did not return turnId")
print(turn_id)
PY
)"

message_payload='{"jsonrpc":"2.0","id":"message","method":"turn/start","params":{"sessionId":"scenario-session-001","threadId":"scenario-session-001","mode":"gateway-chat","taskPrompt":"Continue with a very short acknowledgement.","workingDirectory":"/tmp","selectedSkills":[],"attachments":[],"provider":"codex","routing":{"routingMode":"auto","preferredGatewayTarget":"codex","explicitExecutionTarget":"agent","explicitProviderId":"codex","explicitModel":"","explicitSkills":[],"allowSkillInstall":false,"availableSkills":[]},"requestedExecutionTarget":"agent","executionTarget":"agent"}}'
message_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    "${message_payload}" \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

cancel_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    '{"jsonrpc":"2.0","id":"cancel","method":"session.cancel","params":{"sessionId":"scenario-session-001","threadId":"scenario-session-001"}}' \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

close_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    '{"jsonrpc":"2.0","id":"close","method":"session.close","params":{"sessionId":"scenario-session-001","threadId":"scenario-session-001"}}' \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

RESPONSE_JSON="${session_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
user = payload.get("user")
if not isinstance(user, dict) or user.get("email") != "review@svc.plus":
    raise SystemExit("session payload did not match review account")
PY

RESPONSE_JSON="${capabilities_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
if result.get("availableExecutionTargets") != ["agent", "gateway"]:
    raise SystemExit("scenario capabilities did not expose both execution targets")
PY

RESPONSE_JSON="${start_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
if result.get("resolvedProviderId") != "codex":
    raise SystemExit("thread/start did not resolve codex")
if not str(result.get("error") or "").strip():
    raise SystemExit("thread/start in this environment should expose downstream error details")
PY

RESPONSE_JSON="${message_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
if result.get("turnId") == "":
    raise SystemExit("turn/start did not return turnId")
if str(result.get("turnId") or "").strip() == "":
    raise SystemExit("turn/start did not return turnId")
PY

RESPONSE_JSON="${cancel_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
if result.get("accepted") is not True:
    raise SystemExit("session.cancel was not accepted")
PY

RESPONSE_JSON="${close_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result") or payload.get("payload") or {}
if result.get("closed") is not True:
    raise SystemExit("session.close did not report closed")
PY

printf 'API scenario contract verified via %s (turnId=%s)\n' "${bridge_server_url}" "${turn_id}"
