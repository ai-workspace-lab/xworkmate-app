#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    exec "$SCRIPT_DIR/codex-acp-service-macos.sh" "$@"
    ;;
  Linux)
    exec "$SCRIPT_DIR/codex-acp-service-linux.sh" "$@"
    ;;
  *)
    echo "Unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
