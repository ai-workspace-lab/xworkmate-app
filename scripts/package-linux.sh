#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$repo_root/scripts/package-linux-deb.sh"
bash "$repo_root/scripts/package-linux-rpm.sh"
