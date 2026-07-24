#!/usr/bin/env bash
set -euo pipefail

obs_token="${1:-}"
obs_project="${2:-home:haitaopanhq}"
obs_package="${3:-xworkmate}"
obs_url="${4:-https://build.opensuse.org/trigger/runservice}"

if [ -z "$obs_token" ]; then
  echo "==> [OBS] No OBS_TOKEN provided from Vault, skipping OBS build trigger."
  exit 0
fi

echo "==> [OBS] Triggering Open Build Service build for project '${obs_project}', package '${obs_package}'..."

curl -f -s -X POST \
  -H "Authorization: Token ${obs_token}" \
  "${obs_url}?project=${obs_project}&package=${obs_package}" || {
    echo "==> [OBS] Notice: OBS trigger endpoint returned non-zero response (project/package may require setup on OBS)."
    exit 0
  }

echo "==> [OBS] Trigger request sent successfully."
