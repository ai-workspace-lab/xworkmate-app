#!/usr/bin/env bash
set -euo pipefail

ACCOUNTS_BASE_URL="${REVIEW_ACCOUNT_BASE_URL:-https://accounts.svc.plus}"
REVIEW_ACCOUNT_LOGIN_NAME="${REVIEW_ACCOUNT_LOGIN_NAME:-review@svc.plus}"
REVIEW_ACCOUNT_LOGIN_PASSWORD="${REVIEW_ACCOUNT_LOGIN_PASSWORD:-}"
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

print(json.dumps({
    "identifier": os.environ["REVIEW_ACCOUNT_LOGIN_NAME"],
    "password": os.environ["REVIEW_ACCOUNT_LOGIN_PASSWORD"],
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
token = str(payload.get("token", "")).strip()
if not token:
    raise SystemExit("accounts login response did not include token")
print(token)
PY
)"

sync_json="$(
  json_get \
    "${accounts_base_url}/api/auth/xworkmate/profile/sync" \
    -H "Authorization: Bearer ${session_token}"
)"

bridge_server_url="$(
  RESPONSE_JSON="${sync_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
bridge_url = str(
    payload.get("BRIDGE_SERVER_URL")
    or payload.get("bridgeServerUrl")
    or ""
).strip()
if not bridge_url:
    raise SystemExit("account sync response did not include BRIDGE_SERVER_URL")
print(bridge_url.rstrip("/"))
PY
)"

bridge_auth_token="$(
  RESPONSE_JSON="${sync_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
token = str(payload.get("BRIDGE_AUTH_TOKEN") or "").strip()
if not token:
    raise SystemExit("account sync response did not include BRIDGE_AUTH_TOKEN")
print(token)
PY
)"

capabilities_json="$(
  json_post \
    "${bridge_server_url}/acp/rpc" \
    '{"jsonrpc":"2.0","id":"capabilities","method":"acp.capabilities"}' \
    -H "Authorization: Bearer ${bridge_auth_token}"
)"

RESPONSE_JSON="${capabilities_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RESPONSE_JSON"])
if payload.get("jsonrpc") != "2.0":
    raise SystemExit("bridge capabilities response missing jsonrpc envelope")

result = payload.get("result")
if not isinstance(result, dict):
    raise SystemExit("bridge capabilities response missing result payload")

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

expected_agent_ids = ["codex", "opencode", "gemini"]
expected_agent_labels = ["Codex", "OpenCode", "Gemini"]
if len(provider_catalog) != len(expected_agent_ids):
    raise SystemExit(
        f"expected {len(expected_agent_ids)} agent providers, got {provider_catalog!r}"
    )

for index, (provider_id, label) in enumerate(zip(expected_agent_ids, expected_agent_labels)):
    item = provider_catalog[index]
    if item.get("providerId") != provider_id:
        raise SystemExit(f"expected providerId {provider_id!r} at index {index}, got {item!r}")
    if item.get("label") != label:
        raise SystemExit(f"expected provider label {label!r} at index {index}, got {item!r}")
    if item.get("targets") != ["agent"]:
        raise SystemExit(f"expected agent targets for {provider_id!r}, got {item!r}")

if len(gateway_providers) != 1:
    raise SystemExit(f"expected exactly one gateway provider, got {gateway_providers!r}")

gateway = gateway_providers[0]
if gateway.get("providerId") != "openclaw":
    raise SystemExit(f"expected gateway providerId 'openclaw', got {gateway!r}")
if gateway.get("label") != "OpenClaw":
    raise SystemExit(f"expected gateway label 'OpenClaw', got {gateway!r}")
if gateway.get("targets") != ["gateway"]:
    raise SystemExit(f"expected gateway targets ['gateway'], got {gateway!r}")
PY

printf 'accounts -> bridge provider contract verified via %s\n' "${bridge_server_url}"
