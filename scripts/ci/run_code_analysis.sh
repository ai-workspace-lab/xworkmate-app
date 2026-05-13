#!/usr/bin/env bash
set -euo pipefail

flutter pub get
bash scripts/check-no-app-ffi.sh
flutter analyze
