#!/usr/bin/env bash
set -euo pipefail

# Keep release/profile uploads resilient by generating missing framework dSYMs
# after embed phases. This is a no-op for debug builds.
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

  # Most Flutter and pod frameworks already produce dSYMs in normal archive
  # flow. Keep this pass narrow to known stragglers observed in distribution.
  case "${framework_name}" in
    objective_c|App|A) ;;
    *) continue ;;
  esac

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
