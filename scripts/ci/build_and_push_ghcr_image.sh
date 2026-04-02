#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <registry> <image_repo_owner> <image_tag>" >&2
  exit 1
fi

registry="$1"
image_repo_owner="$2"
image_tag="$3"

image_ref="${registry}/${image_repo_owner}/xworkmate-web:${image_tag}"

docker buildx build \
  --platform linux/amd64 \
  --file lib/web/Dockerfile \
  --tag "${image_ref}" \
  --push \
  .

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "image_tag=${image_tag}"
    echo "image_ref=${image_ref}"
  } >> "${GITHUB_OUTPUT}"
else
  printf 'image_tag=%s\n' "${image_tag}"
  printf 'image_ref=%s\n' "${image_ref}"
fi
