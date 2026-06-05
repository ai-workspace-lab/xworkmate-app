#!/usr/bin/env bash
set -euo pipefail

has_patrol_tests() {
  [[ -d patrol_test ]] && find patrol_test -name '*_test.dart' -print -quit | grep -q .
}

if ! has_patrol_tests; then
  echo "[skip] no Patrol tests found under patrol_test"
  exit 0
fi

flutter pub get
dart pub global activate patrol_cli
patrol test patrol_test
