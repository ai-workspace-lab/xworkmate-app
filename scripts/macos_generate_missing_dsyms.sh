#!/usr/bin/env bash
set -euo pipefail

if [[ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}/Contents/Frameworks"
dsyms_dir="${DWARF_DSYM_FOLDER_PATH:-}"

if [[ -z "${frameworks_dir}" || -z "${dsyms_dir}" || ! -d "${frameworks_dir}" ]]; then
  exit 0
fi

shopt -s nullglob

for framework in "${frameworks_dir}"/*.framework; do
  framework_name="$(basename "${framework}")"
  binary_name="${framework_name%.framework}"
  binary_path="${framework}/${binary_name}"

  if [[ ! -f "${binary_path}" ]]; then
    binary_path="${framework}/Versions/A/${binary_name}"
  fi

  if [[ ! -f "${binary_path}" ]]; then
    continue
  fi

  if ! file "${binary_path}" | grep -q "Mach-O"; then
    continue
  fi

  dsym_path="${dsyms_dir}/${framework_name}.dSYM"
  if [[ -d "${dsym_path}" ]]; then
    continue
  fi

  echo "Generating missing dSYM for ${framework_name}"
  rm -rf "${dsym_path}"
  uuid_output="$(xcrun dwarfdump --uuid "${binary_path}" 2>/dev/null || true)"
  if [[ -z "${uuid_output}" ]]; then
    continue
  fi

  if ! xcrun dsymutil "${binary_path}" -o "${dsym_path}" >/dev/null 2>&1; then
    rm -rf "${dsym_path}"
  fi
done
