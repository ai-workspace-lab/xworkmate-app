#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/App.app" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_PATH="$(cd "$APP_PATH" && pwd -P)"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found: $INFO_PLIST" >&2
  exit 1
fi

APP_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$APP_EXECUTABLE" ]]; then
  echo "Unable to read CFBundleExecutable from $INFO_PLIST" >&2
  exit 1
fi

MAIN_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE"
if [[ ! -x "$MAIN_EXECUTABLE" ]]; then
  echo "Main executable not found: $MAIN_EXECUTABLE" >&2
  exit 1
fi

resolve_special_path() {
  local path="$1"
  local executable_dir="$2"
  local loader_dir="$3"

  path="${path//@executable_path/$executable_dir}"
  path="${path//@loader_path/$loader_dir}"
  printf '%s\n' "$path"
}

normalize_existing_path() {
  local path="$1"
  local dir
  dir="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

extract_rpaths() {
  local binary_path="$1"
  local executable_dir="$2"
  local loader_dir="$3"

  otool -l "$binary_path" 2>/dev/null | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { want = 1; next }
    want && $1 == "path" { print $2; want = 0 }
  ' | while IFS= read -r rpath; do
    resolve_special_path "$rpath" "$executable_dir" "$loader_dir"
  done
}

is_macho_file() {
  local path="$1"
  otool -L "$path" >/dev/null 2>&1
}

resolve_dependency() {
  local dependency="$1"
  local binary_path="$2"
  local app_path="$3"
  local executable_dir="$4"
  local loader_dir
  loader_dir="$(cd "$(dirname "$binary_path")" && pwd)"

  case "$dependency" in
    /System/Library/*|/usr/lib/*)
      return 0
      ;;
    @executable_path/*|@loader_path/*)
      local resolved
      resolved="$(resolve_special_path "$dependency" "$executable_dir" "$loader_dir")"
      [[ -e "$resolved" ]] && {
        normalize_existing_path "$resolved"
        return 0
      }
      return 1
      ;;
    @rpath/*)
      while IFS= read -r rpath; do
        local candidate="${dependency/@rpath/$rpath}"
        candidate="$(resolve_special_path "$candidate" "$executable_dir" "$loader_dir")"
        if [[ -e "$candidate" ]]; then
          normalize_existing_path "$candidate"
          return 0
        fi
      done < <(
        {
          extract_rpaths "$binary_path" "$executable_dir" "$loader_dir"
          printf '%s\n' "$app_path/Contents/Frameworks"
        } | awk '!seen[$0]++'
      )
      return 1
      ;;
    /*)
      if [[ -e "$dependency" ]]; then
        normalize_existing_path "$dependency"
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

validate_binary() {
  local binary_path="$1"
  local app_path="$2"
  local executable_dir="$3"
  local failures=0
  declare -A seen_dependencies=()

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    local dependency
    dependency="$(awk '{print $1}' <<< "$line")"
    [[ "$dependency" == "$binary_path" ]] && continue
    [[ -n "${seen_dependencies[$dependency]:-}" ]] && continue
    seen_dependencies["$dependency"]=1
    local is_weak=0
    [[ "$line" == *" weak)"* ]] && is_weak=1

    if [[ "$dependency" == "/System/Library/"* || "$dependency" == "/usr/lib/"* ]]; then
      continue
    fi

    if ! resolve_dependency "$dependency" "$binary_path" "$app_path" "$executable_dir" >/dev/null; then
      if (( is_weak )); then
        echo "Warning: unresolved weak dependency in $binary_path -> $dependency" >&2
        continue
      fi
      echo "Missing dependency in app bundle:" >&2
      echo "  Binary: $binary_path" >&2
      echo "  Dependency: $dependency" >&2
      ((failures++))
      continue
    fi

    local resolved_path
    resolved_path="$(resolve_dependency "$dependency" "$binary_path" "$app_path" "$executable_dir")"
    case "$resolved_path" in
      /System/Library/*|/usr/lib/*)
        ;;
      "$app_path"/*)
        ;;
      *)
        if (( ! is_weak )); then
          echo "Non-system dependency resolves outside the app bundle:" >&2
          echo "  Binary: $binary_path" >&2
          echo "  Dependency: $dependency" >&2
          echo "  Resolved: $resolved_path" >&2
          ((failures++))
        fi
        ;;
    esac
  done < <(
    otool -L "$binary_path" 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'
  )

  return "$failures"
}

echo "Validating macOS app bundle dynamic dependencies: $APP_PATH"

EXECUTABLE_DIR="$(cd "$APP_PATH/Contents/MacOS" && pwd)"
declare -a macho_files=("$MAIN_EXECUTABLE")

if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' candidate; do
    if is_macho_file "$candidate"; then
      macho_files+=("$candidate")
    fi
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -print0)
fi

declare -A seen_binaries=()
failures=0

for binary_path in "${macho_files[@]}"; do
  [[ -n "${seen_binaries[$binary_path]:-}" ]] && continue
  seen_binaries["$binary_path"]=1

  if ! validate_binary "$binary_path" "$APP_PATH" "$EXECUTABLE_DIR"; then
    failures=1
  fi
done

if (( failures != 0 )); then
  echo "App bundle dependency validation failed: $APP_PATH" >&2
  exit 1
fi

echo "App bundle dependency validation passed: $APP_PATH"
