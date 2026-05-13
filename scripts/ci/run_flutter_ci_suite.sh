#!/usr/bin/env bash
set -euo pipefail

flutter pub get
bash scripts/check-no-app-ffi.sh
flutter analyze
flutter test test/runtime/assistant_execution_target_test.dart
flutter test test/runtime/runtime_controllers_settings_account_test.dart
flutter test test/features/assistant/assistant_lower_pane_test.dart
