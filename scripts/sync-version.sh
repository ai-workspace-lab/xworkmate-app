#!/bin/bash
set -e

# Extract current version from pubspec.yaml if not provided
# but here the user requested: version: 1.1.5+2
TARGET_VERSION="1.1.5+2"
DATE=$(date +%Y-%m-%d)
COMMIT=$(git rev-parse --short HEAD)

# Update version in pubspec.yaml
sed -i.bak -e "s/^version: .*/version: ${TARGET_VERSION}/" \
           -e "s/^build-date: .*/build-date: ${DATE}/" \
           -e "s/^build-id: .*/build-id: ${COMMIT}/" pubspec.yaml

rm -f pubspec.yaml.bak

echo "Updated pubspec.yaml to version=${TARGET_VERSION}, build-date=${DATE}, build-id=${COMMIT}"
