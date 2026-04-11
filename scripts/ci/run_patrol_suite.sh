#!/usr/bin/env bash
set -euo pipefail

flutter pub get
dart pub global activate patrol_cli
patrol test
