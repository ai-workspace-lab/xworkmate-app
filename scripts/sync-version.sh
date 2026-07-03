#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sync-version.sh [--version VERSION] [--commit COMMIT]

Updates pubspec.yaml version metadata. When --commit is not provided, the
script falls back to BUILD_COMMIT, then git HEAD.
EOF
}

TARGET_VERSION=""
TARGET_COMMIT="${BUILD_COMMIT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      TARGET_VERSION="${2:-}"
      shift 2
      ;;
    --commit)
      TARGET_COMMIT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$TARGET_VERSION" ]]; then
  :
else
  # Extract current version from pubspec.yaml
  CURRENT_VERSION=$(grep "^version: " pubspec.yaml | awk '{print $2}')
  
  if [[ "$CURRENT_VERSION" == *"+"* ]]; then
    BASE_VERSION=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
    BUILD_NUM=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)
    NEXT_BUILD_NUM=$((BUILD_NUM + 1))
    TARGET_VERSION="${BASE_VERSION}+${NEXT_BUILD_NUM}"
  else
    TARGET_VERSION="${CURRENT_VERSION}+1"
  fi
fi
DATE=$(date +%Y-%m-%d)
if [[ -z "$TARGET_COMMIT" ]]; then
  TARGET_COMMIT=$(git rev-parse --short HEAD)
fi

# Update version in pubspec.yaml
sed -i.bak -e "s/^version: .*/version: ${TARGET_VERSION}/" \
           -e "s/^build-date: .*/build-date: ${DATE}/" \
           -e "s/^build-id: .*/build-id: ${TARGET_COMMIT}/" pubspec.yaml

rm -f pubspec.yaml.bak

echo "Updated pubspec.yaml to version=${TARGET_VERSION}, build-date=${DATE}, build-id=${TARGET_COMMIT}"
