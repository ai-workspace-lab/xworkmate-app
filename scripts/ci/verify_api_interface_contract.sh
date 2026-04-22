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

expect_json() {
  RESPONSE_JSON="${1}" python3 - "$2" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE_JSON"])
mode = sys.argv[1]

if mode == "accounts":
    if "token" not in payload and "access_token" not in payload:
        raise SystemExit("accounts login response did not include token")
    if "user" not in payload:
        raise SystemExit("accounts login response did not include user payload")
elif mode == "sync":
    bridge_url = str(payload.get("BRIDGE_SERVER_URL") or "").strip()
    bridge_token = str(payload.get("BRIDGE_AUTH_TOKEN") or "").strip()
    if not bridge_url:
        raise SystemExit("sync response did not include BRIDGE_SERVER_URL")
    if not bridge_token:
        raise SystemExit("sync response did not include BRIDGE_AUTH_TOKEN")
elif mode == "capabilities":
    if payload.get("jsonrpc") != "2.0":
        raise SystemExit("capabilities response missing jsonrpc envelope")
    result = payload.get("result")
    if not isinstance(result, dict):
        raise SystemExit("capabilities response missing result payload")
    expected_targets = ["agent", "gateway"]
    if result.get("availableExecutionTargets") != expected_targets:
        raise SystemExit(
            f"expected availableExecutionTargets {expected_targets!r}, got {result.get('availableExecutionTargets')!r}"
        )
    provider_catalog = result.get("providerCatalog")
    if not isinstance(provider_catalog, list):
        raise SystemExit("providerCatalog is missing or invalid")
    gateway_providers = result.get("gatewayProviders")
    if not isinstance(gateway_providers, list):
        raise SystemExit("gatewayProviders is missing or invalid")
    provider_ids = [str(item.get("providerId")) for item in provider_catalog]
    if provider_ids != ["codex", "opencode", "gemini", "hermes"]:
        raise SystemExit(f"unexpected providerCatalog: {provider_ids!r}")
    if len(gateway_providers) != 1 or gateway_providers[0].get("providerId") != "openclaw":
        raise SystemExit(f"unexpected gatewayProviders: {gateway_providers!r}")
elif mode == "routing":
    if payload.get("jsonrpc") != "2.0":
        raise SystemExit("routing response missing jsonrpc envelope")
    result = payload.get("result")
    if not isinstance(result, dict):
        raise SystemExit("routing response missing result payload")
    if result.get("resolvedExecutionTarget") != "single-agent":
        raise SystemExit(
            f"unexpected resolvedExecutionTarget: {result.get('resolvedExecutionTarget')!r}"
        )
    if result.get("resolvedProviderId") != "codex":
        raise SystemExit(
            f"unexpected resolvedProviderId: {result.get('resolvedProviderId')!r}"
        )
    if bool(result.get("unavailable")):
        raise SystemExit(f"routing unexpectedly unavailable: {result!r}")
else:
    raise SystemExit(f"unknown expectation mode: {mode}")
PY
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
RESPONSE_JSON="${session_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
user = payload.get("user")
if not isinstance(user, dict) or not user.get("email"):
    raise SystemExit("session response did not include user email")
PY

sync_json="$(
  json_get \
    "${accounts_base_url}/api/auth/xworkmate/profile/sync" \
    -H "Authorization: Bearer ${session_token}"
)"
RESPONSE_JSON="${sync_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
bridge_url = str(payload.get("BRIDGE_SERVER_URL") or payload.get("bridgeServerUrl") or "").strip()
bridge_token = str(payload.get("BRIDGE_AUTH_TOKEN") or "").strip()
if not bridge_url:
    raise SystemExit("sync response did not include BRIDGE_SERVER_URL")
if not bridge_token:
    raise SystemExit("sync response did not include BRIDGE_AUTH_TOKEN")
PY

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
RESPONSE_JSON="${capabilities_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result")
if not isinstance(result, dict):
    raise SystemExit("capabilities response missing result payload")
if result.get("availableExecutionTargets") != ["agent", "gateway"]:
    raise SystemExit("unexpected availableExecutionTargets")
PY

routing_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    '{
      "jsonrpc":"2.0",
      "id":"routing",
      "method":"xworkmate.routing.resolve",
      "params":{
        "taskPrompt":"check api",
        "workingDirectory":"/tmp",
        "routing":{
          "routingMode":"auto",
          "preferredGatewayTarget":"codex",
          "explicitExecutionTarget":"agent",
          "explicitProviderId":"codex",
          "explicitModel":"",
          "explicitSkills":[],
          "allowSkillInstall":false,
          "availableSkills":[]
        }
      }
    }' \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"
RESPONSE_JSON="${routing_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
result = payload.get("result")
if not isinstance(result, dict):
    raise SystemExit("routing response missing result payload")
if result.get("resolvedProviderId") != "codex":
    raise SystemExit("unexpected resolvedProviderId")
PY

printf 'API interface contract verified via %s\n' "${bridge_server_url}"
