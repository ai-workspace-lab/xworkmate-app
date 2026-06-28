#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-all}"

# Desktop integration tests launch the real GTK app, which needs a display
# server. On a headless Linux CI runner there is none, so the app never
# establishes a debug connection ("The log reader stopped unexpectedly, or
# never started"). Wrap such commands in a virtual framebuffer when one is
# available; on macOS/local runs (no xvfb-run) the command runs unchanged.
with_display() {
  if [[ "$(uname -s)" == "Linux" ]] && command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a --server-args="-screen 0 1920x1080x24" "$@"
  else
    "$@"
  fi
}

run_flutter_base() {
  flutter pub get
  flutter analyze
}

run_flutter_unit_widget() {
  local test_dirs=()
  local candidate
  for candidate in test/widgets test/features test/runtime test/app test/theme test/web; do
    if [[ -d "$candidate" ]] && find "$candidate" -name '*_test.dart' | grep -q .; then
      test_dirs+=("$candidate")
    fi
  done
  if [[ "${#test_dirs[@]}" -eq 0 ]]; then
    echo "[skip] no unit/widget tests found"
    return
  fi
  flutter test "${test_dirs[@]}"
}

run_flutter_golden_if_present() {
  if [[ -d test/golden ]] && find test/golden -name '*_test.dart' | grep -q .; then
    flutter test test/golden
  else
    echo "[skip] no golden tests found under test/golden"
  fi
}

run_flutter_integration_if_present() {
  if [[ -d integration_test ]] && find integration_test -name '*_test.dart' | grep -q .; then
    with_display flutter test integration_test
  else
    echo "[skip] no integration tests found under integration_test"
  fi
}

run_patrol_if_present() {
  if command -v patrol >/dev/null 2>&1 && [[ -d patrol_test ]] && find patrol_test -name '*_test.dart' | grep -q .; then
    with_display patrol test patrol_test
  else
    echo "[skip] patrol not installed or patrol_test is empty"
  fi
}

case "$LAYER" in
  pr)
    run_flutter_base
    run_flutter_unit_widget
    run_flutter_golden_if_present
    ;;
  e2e)
    run_flutter_base
    run_flutter_integration_if_present
    run_patrol_if_present
    ;;
  all)
    run_flutter_base
    run_flutter_unit_widget
    run_flutter_golden_if_present
    run_flutter_integration_if_present
    run_patrol_if_present
    ;;
  *)
    echo "Usage: $0 [pr|e2e|all]"
    exit 2
    ;;
esac
