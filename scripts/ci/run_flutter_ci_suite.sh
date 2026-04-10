#!/usr/bin/env bash
set -euo pipefail

flutter pub get
flutter analyze
flutter test
flutter test test/golden
flutter test integration_test
