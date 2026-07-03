#!/usr/bin/env bash
set -euo pipefail

flutter pub get
bash scripts/check-no-app-ffi.sh
bash scripts/ci/test_sync_version.sh
flutter analyze
