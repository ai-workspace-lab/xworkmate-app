#!/bin/bash
set -e

if [ -n "$1" ]; then
  TARGET_VERSION="$1"
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
COMMIT=$(git rev-parse --short HEAD)

# Update version in pubspec.yaml
sed -i.bak -e "s/^version: .*/version: ${TARGET_VERSION}/" \
           -e "s/^build-date: .*/build-date: ${DATE}/" \
           -e "s/^build-id: .*/build-id: ${COMMIT}/" pubspec.yaml

rm -f pubspec.yaml.bak

echo "Updated pubspec.yaml to version=${TARGET_VERSION}, build-date=${DATE}, build-id=${COMMIT}"
