#!/usr/bin/env bash
set -euo pipefail

# Generates Casks/xworkmate.rb for a macOS DMG release artifact and optionally
# commits and pushes it to the Homebrew tap repository.

DMG_PATH=""
ARM64_DMG_PATH=""
X86_64_DMG_PATH=""
VERSION=""
RELEASE_TAG=""
TAP_REPO="${HOMEBREW_TAP_REPO:-ai-workspace-lab/homebrew-tap}"
SOURCE_REPO="${GITHUB_REPOSITORY:-ai-workspace-lab/xworkmate-app}"
OUTPUT_PATH=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: update_homebrew_cask.sh [options]

Options:
  --dmg <path>         Path to a single macOS .dmg release artifact
  --arm64-dmg <path>   Path to the macOS arm64 .dmg release artifact
  --x86_64-dmg <path>  Path to the macOS x86_64 .dmg release artifact
  --version <ver>      Display version for the cask (required, e.g. 1.2.0)
  --tag <tag>          GitHub release tag (required, e.g. v1.2.0)
  --tap-repo <repo>    Target Homebrew tap repo (default: ai-workspace-lab/homebrew-tap)
  --source-repo <repo> Source GitHub repo (default: ai-workspace-lab/xworkmate-app)
  --output <path>      Write generated cask to this path instead of/before pushing
  --dry-run            Generate cask without cloning or pushing to the tap repo
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --arm64-dmg)
      ARM64_DMG_PATH="${2:-}"
      shift 2
      ;;
    --x86_64-dmg)
      X86_64_DMG_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="${2:-}"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="${2:-}"
      shift 2
      ;;
    --source-repo)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$RELEASE_TAG" ]]; then
  echo "Error: --version and --tag are required." >&2
  usage >&2
  exit 1
fi

if [[ -n "$ARM64_DMG_PATH" && -n "$X86_64_DMG_PATH" ]]; then
  for dmg_candidate in "$ARM64_DMG_PATH" "$X86_64_DMG_PATH"; do
    if [[ ! -f "$dmg_candidate" ]]; then
      echo "Error: DMG file not found: $dmg_candidate" >&2
      exit 1
    fi
  done
elif [[ -n "$DMG_PATH" ]]; then
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG file not found: $DMG_PATH" >&2
    exit 1
  fi
else
  echo "Error: provide either --dmg or both --arm64-dmg and --x86_64-dmg." >&2
  usage >&2
  exit 1
fi

compute_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "Error: neither sha256sum nor shasum is available." >&2
    exit 1
  fi
}

# Strip leading 'v' if present for the Homebrew cask version field.
CASK_VERSION="${VERSION#v}"

format_url_filename() {
  local dmg_filename
  dmg_filename="$(basename "$1")"
  if [[ "$dmg_filename" == *"$CASK_VERSION"* ]]; then
    printf '%s\n' "${dmg_filename//$CASK_VERSION/\#{version\}}"
  else
    printf '%s\n' "$dmg_filename"
  fi
}

if [[ "$RELEASE_TAG" == "v$CASK_VERSION" ]]; then
  URL_TAG="v#{version}"
elif [[ "$RELEASE_TAG" == "$CASK_VERSION" ]]; then
  URL_TAG="#{version}"
else
  URL_TAG="$RELEASE_TAG"
fi

render_cask() {
  cat <<EOF
cask "xworkmate" do
  version "${CASK_VERSION}"
EOF

  if [[ -n "$ARM64_DMG_PATH" && -n "$X86_64_DMG_PATH" ]]; then
    local arm64_sha x86_64_sha arm64_file x86_64_file
    arm64_sha="$(compute_sha256 "$ARM64_DMG_PATH")"
    x86_64_sha="$(compute_sha256 "$X86_64_DMG_PATH")"
    arm64_file="$(format_url_filename "$ARM64_DMG_PATH")"
    x86_64_file="$(format_url_filename "$X86_64_DMG_PATH")"
    cat <<EOF
  arch arm: "arm64", intel: "x86_64"

  sha256 arm:   "${arm64_sha}",
         intel: "${x86_64_sha}"

  on_arm do
    url "https://github.com/${SOURCE_REPO}/releases/download/${URL_TAG}/${arm64_file}"
  end
  on_intel do
    url "https://github.com/${SOURCE_REPO}/releases/download/${URL_TAG}/${x86_64_file}"
  end
EOF
  else
    local single_sha single_file
    single_sha="$(compute_sha256 "$DMG_PATH")"
    single_file="$(format_url_filename "$DMG_PATH")"
    cat <<EOF
  sha256 "${single_sha}"

  url "https://github.com/${SOURCE_REPO}/releases/download/${URL_TAG}/${single_file}"
EOF
  fi

  cat <<EOF
  name "XWorkmate"
  desc "Desktop-first AI workspace shell"
  homepage "https://github.com/${SOURCE_REPO}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "XWorkmate.app"

  zap trash: [
    "~/Library/Application Support/plus.svc.xworkmate",
    "~/Library/Caches/plus.svc.xworkmate",
    "~/Library/Preferences/plus.svc.xworkmate.plist",
    "~/Library/Saved Application State/plus.svc.xworkmate.savedState",
  ]
end
EOF
}

if [[ -n "$OUTPUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  render_cask > "$OUTPUT_PATH"
  echo "Wrote Homebrew cask to $OUTPUT_PATH"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ -z "$OUTPUT_PATH" ]]; then
    render_cask
  fi
  echo "Dry run complete; skipping git push to $TAP_REPO."
  exit 0
fi

TOKEN="${HOMEBREW_TAP_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Error: HOMEBREW_TAP_TOKEN is not set. Cannot push to $TAP_REPO." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_URL="https://x-access-token:${TOKEN}@github.com/${TAP_REPO}.git"
git clone --depth 1 "$CLONE_URL" "$TMP_DIR/tap"

mkdir -p "$TMP_DIR/tap/Casks"
render_cask > "$TMP_DIR/tap/Casks/xworkmate.rb"

cd "$TMP_DIR/tap"
if git diff --quiet && [[ -z "$(git status --porcelain Casks/xworkmate.rb)" ]]; then
  echo "Casks/xworkmate.rb is already up to date for ${CASK_VERSION}."
  exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
git add Casks/xworkmate.rb
git commit -m "chore(cask): update xworkmate to ${CASK_VERSION}"
git push origin HEAD

echo "Successfully updated ${TAP_REPO} Casks/xworkmate.rb to ${CASK_VERSION}."
