#!/usr/bin/env bash
#
# Publish the staged RPM sources to Open Build Service.
#
# Two modes, picked from whichever credentials are available:
#
#   osc     OBS_USERNAME + OBS_PASSWORD -- commits tarball/spec/rpmlintrc into
#           the OBS package, which is what actually ships a new version.
#   token   OBS_TOKEN -- POSTs to /trigger/runservice, which only re-runs the
#           source services already configured on the OBS package.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

obs_token="${1:-${OBS_TOKEN:-}}"
obs_project="${2:-${OBS_PROJECT:-home:haitaopanhq}}"
obs_package="${3:-${OBS_PACKAGE:-xworkmate}}"
obs_api_url="${OBS_API_URL:-https://api.opensuse.org}"
obs_username="${OBS_USERNAME:-}"
obs_password="${OBS_PASSWORD:-}"
source_dir="${OBS_SOURCE_DIR:-$repo_root/dist/obs}"
require_publish="${OBS_REQUIRE_PUBLISH:-true}"

tmp_root="$(mktemp -d)"
chmod 700 "$tmp_root"
trap 'rm -rf "$tmp_root"' EXIT

fail_or_skip() {
  local message="$1"
  if [[ "$require_publish" == "true" ]]; then
    echo "==> [OBS] $message" >&2
    exit 1
  fi
  echo "==> [OBS] $message Skipping (OBS_REQUIRE_PUBLISH=false)."
  exit 0
}

publish_with_osc() {
  if ! command -v osc >/dev/null 2>&1; then
    echo "==> [OBS] 'osc' is not installed but OBS_USERNAME/OBS_PASSWORD were provided." >&2
    echo "          On Ubuntu: sudo apt-get install -y osc" >&2
    exit 1
  fi

  local tarball spec rpmlintrc
  tarball="$(find "$source_dir" -maxdepth 1 -name '*.tar.gz' | sort | head -n 1)"
  spec="$source_dir/${obs_package}.spec"
  rpmlintrc="$source_dir/${obs_package}-rpmlintrc"

  if [[ -z "$tarball" || ! -f "$spec" ]]; then
    echo "==> [OBS] Expected a tarball and $spec under $source_dir." >&2
    echo "          Run scripts/package-rpm-source.sh (or download the build artefact) first." >&2
    exit 1
  fi

  local osc_home="$tmp_root/osc-home"
  mkdir -p "$osc_home/.config/osc"
  cat > "$osc_home/.config/osc/oscrc" <<EOF
[general]
apiurl = $obs_api_url

[$obs_api_url]
user = $obs_username
pass = $obs_password
credentials_mgr_class=osc.credentials.PlaintextConfigFileCredentialsManager
EOF
  chmod 600 "$osc_home/.config/osc/oscrc"
  export HOME="$osc_home"

  echo "==> [OBS] Checking package ${obs_project}/${obs_package}..."
  if ! osc -A "$obs_api_url" api "/source/${obs_project}/${obs_package}/_meta" >/dev/null 2>&1; then
    echo "==> [OBS] Package not found; creating it..."
    cat > "$osc_home/meta.xml" <<EOF
<package name="${obs_package}" project="${obs_project}">
  <title>XWorkmate</title>
  <description>XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration.</description>
  <url>https://github.com/ai-workspace-lab/xworkmate-app</url>
</package>
EOF
    osc -A "$obs_api_url" meta pkg "$obs_project" "$obs_package" -F "$osc_home/meta.xml"
  fi

  local workdir="$tmp_root/work"
  mkdir -p "$workdir"
  echo "==> [OBS] Checking out ${obs_project}/${obs_package}..."
  (cd "$workdir" && osc -A "$obs_api_url" checkout "$obs_project" "$obs_package")

  local pkgdir="$workdir/$obs_project/$obs_package"
  echo "==> [OBS] Replacing sources with the staged upload set..."
  find "$pkgdir" -maxdepth 1 -type f \
    \( -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.spec' -o -name '*-rpmlintrc' \) -delete
  cp "$tarball" "$pkgdir/"
  cp "$spec" "$pkgdir/"
  if [[ -f "$rpmlintrc" ]]; then
    cp "$rpmlintrc" "$pkgdir/"
  fi

  local version
  version="$(awk '/^Version:/ {print $2; exit}' "$spec")"

  (
    cd "$pkgdir"
    osc -A "$obs_api_url" addremove
    if osc -A "$obs_api_url" status | grep -q .; then
      osc -A "$obs_api_url" commit -m "Automated build of XWorkmate ${version} (${GITHUB_SHA:-local})"
    else
      echo "==> [OBS] Sources are already identical to the published version; nothing to commit."
    fi
  )

  echo "==> [OBS] Published to ${obs_project}/${obs_package}."
  echo "==> [OBS] Track the builds at https://build.opensuse.org/package/show/${obs_project}/${obs_package}"
}

trigger_with_token() {
  local trigger_url="${OBS_TRIGGER_URL:-${obs_api_url}/trigger/runservice}"
  local response_body="$tmp_root/obs-trigger-response"
  local http_code

  echo "==> [OBS] Triggering runservice for ${obs_project}/${obs_package}..."
  http_code="$(curl -sS -o "$response_body" -w '%{http_code}' -X POST \
    -H "Authorization: Token ${obs_token}" \
    "${trigger_url}?project=${obs_project}&package=${obs_package}")"

  # curl reports 000 when it never got a response, which is a failure even
  # though it does not compare as one.
  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "==> [OBS] Trigger failed with HTTP ${http_code}:" >&2
    cat "$response_body" >&2
    echo "          A token can only re-run source services that are already" >&2
    echo "          configured on the OBS package. To upload new sources from CI," >&2
    echo "          provide OBS_USERNAME and OBS_PASSWORD instead." >&2
    exit 1
  fi

  cat "$response_body"
  echo "==> [OBS] Trigger accepted (HTTP ${http_code})."
}

if [[ -n "$obs_username" && -n "$obs_password" ]]; then
  publish_with_osc
elif [[ -n "$obs_token" ]]; then
  echo "==> [OBS] No OBS_USERNAME/OBS_PASSWORD; falling back to token trigger."
  trigger_with_token
else
  fail_or_skip "No OBS credentials available (need OBS_USERNAME + OBS_PASSWORD, or OBS_TOKEN)."
fi
