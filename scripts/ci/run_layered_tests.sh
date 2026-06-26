#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-all}"

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
    flutter test integration_test
  else
    echo "[skip] no integration tests found under integration_test"
  fi
}

run_patrol_if_present() {
  if command -v patrol >/dev/null 2>&1 && [[ -d patrol_test ]] && find patrol_test -name '*_test.dart' | grep -q .; then
    patrol test patrol_test
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
