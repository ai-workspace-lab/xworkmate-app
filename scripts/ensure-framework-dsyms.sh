#!/usr/bin/env bash
set -euo pipefail

# Generate dSYMs that App Store validation expects for embedded frameworks.
# Some prebuilt dependencies, including WebRTC, do not ship a dSYM even though
# their Mach-O binaries contain UUIDs that App Store Connect requires.
if [[ "${CONFIGURATION:-}" != "Release" && "${CONFIGURATION:-}" != "Profile" ]]; then
  exit 0
fi

if [[ -z "${FRAMEWORKS_FOLDER_PATH:-}" || -z "${TARGET_BUILD_DIR:-}" ]]; then
  exit 0
fi

if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
if [[ ! -d "${frameworks_dir}" ]]; then
  exit 0
fi

mkdir -p "${DWARF_DSYM_FOLDER_PATH}"

dsym_matches_binary() {
  local binary_path="$1"
  local dsym_path="$2"
  local binary_uuids dsym_uuids uuid

  [[ -d "${dsym_path}" ]] || return 1

  binary_uuids="$(xcrun dwarfdump --uuid "${binary_path}" 2>/dev/null || true)"
  dsym_uuids="$(xcrun dwarfdump --uuid "${dsym_path}" 2>/dev/null || true)"
  [[ -n "${binary_uuids}" && -n "${dsym_uuids}" ]] || return 1

  while read -r uuid; do
    [[ -z "${uuid}" ]] || grep -Fq "${uuid}" <<<"${dsym_uuids}" || return 1
  done < <(awk '/^UUID:/ { print $2 }' <<<"${binary_uuids}")
}

for framework_path in "${frameworks_dir}"/*.framework; do
  [[ -d "${framework_path}" ]] || continue

  framework_name="$(basename "${framework_path}" .framework)"
  binary_path="${framework_path}/${framework_name}"
  [[ -f "${binary_path}" ]] || continue

  dsym_path="${DWARF_DSYM_FOLDER_PATH}/${framework_name}.framework.dSYM"
  if dsym_matches_binary "${binary_path}" "${dsym_path}"; then
    continue
  fi

  if ! xcrun dwarfdump --uuid "${binary_path}" >/dev/null 2>&1; then
    continue
  fi

  echo "Generating missing or mismatched dSYM for ${framework_name}.framework"
  rm -rf "${dsym_path}"
  if ! xcrun dsymutil "${binary_path}" -o "${dsym_path}" >/dev/null 2>&1; then
    echo "warning: Failed to generate dSYM for ${framework_name}.framework" >&2
    rm -rf "${dsym_path}" || true
  fi
done
