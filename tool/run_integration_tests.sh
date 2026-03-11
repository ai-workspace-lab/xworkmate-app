#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  pkill -f '/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate' || true
}

trap cleanup EXIT

cd "$ROOT_DIR"

cleanup
flutter test integration_test/desktop_navigation_flow_test.dart -d macos
cleanup
flutter test integration_test/desktop_settings_flow_test.dart -d macos
