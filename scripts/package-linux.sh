#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repo_root/scripts/package-linux-deb.sh"
"$repo_root/scripts/package-linux-rpm.sh"
