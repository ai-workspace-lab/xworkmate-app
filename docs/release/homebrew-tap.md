# Homebrew Tap Publishing

XWorkmate distributes its macOS `.dmg` release via a Homebrew Cask in `ai-workspace-lab/homebrew-tap`.

## User Installation

```bash
brew install --cask ai-workspace-lab/tap/xworkmate
```

Or by tapping first:

```bash
brew tap ai-workspace-lab/tap
brew install --cask xworkmate
```

To upgrade:

```bash
brew upgrade --cask xworkmate
```

## CI Automation

The `homebrew_tap` job in [build-and-release.yml](../../.github/workflows/build-and-release.yml) runs after `release` succeeds:

1. Loads `HOMEBREW_TAP_TOKEN` from Vault (`kv/data/github-actions/xworkmate-app`).
2. Downloads the `build-macos-arm64-dmg` artifact.
3. Runs [update_homebrew_cask.sh](../../scripts/ci/update_homebrew_cask.sh) to compute the `.dmg` SHA-256, render `Casks/xworkmate.rb`, and push the update to `ai-workspace-lab/homebrew-tap`.
   - If `HOMEBREW_TAP_TOKEN` is not yet configured in Vault, the job falls back to `--dry-run` so releases are not blocked.

## Repository & Secret Setup

1. Create the public GitHub repository `ai-workspace-lab/homebrew-tap` (with a `Casks/` directory).
2. Create a fine-grained GitHub Personal Access Token (or GitHub App token) with `Contents: Read and write` permission on `ai-workspace-lab/homebrew-tap`.
3. Store the token in Vault at `kv/data/github-actions/xworkmate-app` under the key `HOMEBREW_TAP_TOKEN`.

## Local Dry-Run

```bash
bash ./scripts/ci/update_homebrew_cask.sh \
  --dmg dist/macos/XWorkmate-1.2.0.dmg \
  --version 1.2.0 \
  --tag v1.2.0 \
  --dry-run
```
