#!/usr/bin/env bash
set -euo pipefail

obs_token="${1:-}"

if [ -z "$obs_token" ]; then
  echo "==> [OBS] No OBS_TOKEN provided from Vault, skipping OBS build trigger."
  exit 0
fi

echo "==> [OBS] Triggering Open Build Service build for xworkmate..."

curl -f -s -X POST \
  -H "Authorization: Token ${obs_token}" \
  "https://build.opensuse.org/trigger/runservice?project=home:haitaopanhq&package=xworkmate" || {
    echo "==> [OBS] Notice: OBS trigger endpoint returned non-zero response (project/package may require setup on OBS)."
    exit 0
  }

echo "==> [OBS] Trigger request sent successfully."
