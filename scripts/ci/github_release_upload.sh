#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-release-artifacts}"
tag="${RELEASE_TAG:-manual-${GITHUB_RUN_NUMBER:-0}}"
title="${RELEASE_TITLE:-Manual Build ${GITHUB_RUN_NUMBER:-0}}"
notes="${RELEASE_NOTES:-Automated build}"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required to upload release artifacts." >&2
  exit 1
fi

mapfile -d '' files < <(find "$artifact_dir" -type f -print0)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No release artifacts found in $artifact_dir" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -z "${DISPLAY_VERSION:-}" && -f "$repo_root/scripts/ci/build_version.py" ]]; then
  eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell 2>/dev/null || true)"
fi

if gh release view "$tag" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  if gh release view "$tag" --repo "${GITHUB_REPOSITORY}" --json isImmutable --jq '.isImmutable' 2>/dev/null | grep -q '^true$'; then
    echo "Release $tag is immutable on GitHub." >&2
    display_ver="${DISPLAY_VERSION:-}"
    if [[ -z "$display_ver" ]]; then
      display_ver="1.1.10"
    fi
    
    fallback_tag="v${display_ver}"
    if [[ "$fallback_tag" == "$tag" ]] || (gh release view "$fallback_tag" --repo "${GITHUB_REPOSITORY}" --json isImmutable --jq '.isImmutable' 2>/dev/null | grep -q '^true$'); then
      fallback_tag="v${display_ver}-build.${GITHUB_RUN_NUMBER:-0}"
    fi
    echo "Falling back to release tag $fallback_tag for asset publication." >&2
    tag="$fallback_tag"
    title="Release ${fallback_tag}"
  fi
fi

if ! gh release view "$tag" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  echo "Creating release $tag with title '$title'..."
  gh release create "$tag" --repo "${GITHUB_REPOSITORY}" --title "$title" --notes "$notes" "${files[@]}"
  exit 0
fi

echo "Updating release $tag..."
gh release edit "$tag" --repo "${GITHUB_REPOSITORY}" --title "$title" --notes "$notes"

for file in "${files[@]}"; do
  echo "Uploading $file to release $tag..."
  gh release upload "$tag" "$file" --repo "${GITHUB_REPOSITORY}" --clobber
done
