#!/usr/bin/env bash
set -euo pipefail

LAYER="${1:-all}"

run_flutter_base() {
  flutter pub get
  flutter analyze
}

run_flutter_unit_widget() {
  flutter test test/widgets test/features test/runtime test/app test/theme test/web
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

run_go_unit() {
  (cd go/go_core && go test ./...)
}

case "$LAYER" in
  pr)
    run_flutter_base
    run_flutter_unit_widget
    run_flutter_golden_if_present
    run_go_unit
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
    run_go_unit
    ;;
  *)
    echo "Usage: $0 [pr|e2e|all]"
    exit 2
    ;;
esac
