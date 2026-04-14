#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  release_tag="${GITHUB_REF_NAME}"
  release_title="Release ${GITHUB_REF_NAME}"
  release_notes="Automated release for ${DISPLAY_VERSION}"
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]]; then
  release_tag="manual-${GITHUB_RUN_NUMBER:-0}"
  release_title="Manual Build ${GITHUB_RUN_NUMBER:-0} (${DISPLAY_VERSION})"
  release_notes="Automated manual build ${DISPLAY_VERSION} from ${GITHUB_SHA:-unknown}"
elif [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
  release_tag="latest"
  release_title="Latest"
  release_notes="Automated latest main build ${DISPLAY_VERSION} from ${GITHUB_SHA:-unknown}"
else
  release_tag="main-${GITHUB_RUN_NUMBER:-0}"
  release_title="Main Build ${GITHUB_RUN_NUMBER:-0} (${DISPLAY_VERSION})"
  release_notes="Automated build ${DISPLAY_VERSION} from ${GITHUB_SHA:-unknown}"
fi

{
  echo "release_tag=${release_tag}"
  echo "release_title=${release_title}"
  echo "release_notes=${release_notes}"
} >> "$GITHUB_OUTPUT"
