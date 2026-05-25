#!/usr/bin/env bash
set -euo pipefail

# Generate the dSYM that App Store validation expects for the vendored
# objective_c native-asset framework after Xcode/CocoaPods embed it.
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

for framework_path in "${frameworks_dir}"/*.framework; do
  [[ -d "${framework_path}" ]] || continue

  framework_name="$(basename "${framework_path}" .framework)"
  binary_path="${framework_path}/${framework_name}"
  [[ -f "${binary_path}" ]] || continue

  [[ "${framework_name}" == "objective_c" ]] || continue

  dsym_path="${DWARF_DSYM_FOLDER_PATH}/${framework_name}.framework.dSYM"
  if [[ -d "${dsym_path}" ]]; then
    continue
  fi

  if ! xcrun dwarfdump --uuid "${binary_path}" >/dev/null 2>&1; then
    continue
  fi

  echo "Generating missing dSYM for ${framework_name}.framework"
  if ! xcrun dsymutil "${binary_path}" -o "${dsym_path}" >/dev/null 2>&1; then
    echo "warning: Failed to generate dSYM for ${framework_name}.framework" >&2
    rm -rf "${dsym_path}" || true
  fi
done
