# Homebrew Tap Publishing

XWorkmate distributes its macOS `.dmg` release via a Homebrew Cask in `ai-workspace-lab/homebrew-tap`.

## Distribution Strategy

1. **Phase 1 — Self-Hosted Tap (Current)**:
   - Publish `Casks/xworkmate.rb` to `ai-workspace-lab/homebrew-tap` via CI.
   - Users install with `brew install --cask ai-workspace-lab/tap/xworkmate`.
2. **Phase 2 — Official `homebrew/homebrew-cask` (Future)**:
   - Once the repository reaches **GitHub Stars ≥ 75** or demonstrates stable download/usage volume, submit `Casks/xworkmate.rb` via PR to `Homebrew/homebrew-cask` (`Casks/x/xworkmate.rb`) and verify with `brew audit --cask --online`.
   - Once merged, users can install directly with `brew install --cask xworkmate`.

## User Installation

```bash
brew tap ai-workspace-lab/tap
brew trust ai-workspace-lab/tap   # Required on Homebrew 7+ for third-party taps
brew install --cask ai-workspace-lab/tap/xworkmate
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

1. **Create the Tap Repository**
   - Create the public GitHub repository `ai-workspace-lab/homebrew-tap` and initialize its default branch (`main`).

2. **Generate `HOMEBREW_TAP_TOKEN` (Fine-grained PAT)**
   - In GitHub, go to **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
   - **Token name**: e.g. `xworkmate-homebrew-tap`.
   - **Resource owner**: `ai-workspace-lab` (requires org admin approval if the organization enforces Fine-grained PAT approval).
   - **Expiration**: choose according to your security policy (e.g. 90 days or 1 year).
   - **Repository access**: **Only select repositories** → select `ai-workspace-lab/homebrew-tap`.
   - **Repository permissions**: set **Contents** to **Read and write**; leave all other permissions as **No access**.
   - Click **Generate token** and copy the `github_pat_...` value.
   - *(Fallback if Fine-grained PAT is disabled)*: use **Tokens (classic)** with `public_repo` (for a public tap) or `repo` scope.

3. **Store the Token in Vault**
   - Use `vault kv patch` (not `vault kv put`) so existing secrets under `kv/github-actions/xworkmate-app` are preserved:

   ```bash
   export VAULT_ADDR="https://vault.svc.plus"

   vault kv patch kv/github-actions/xworkmate-app \
     HOMEBREW_TAP_TOKEN="github_pat_your_token"
   ```

   - Verify the key exists:

   ```bash
   vault kv get -format=json kv/github-actions/xworkmate-app | jq -r '.data.data | keys[]'
   ```

## Local Dry-Run

```bash
bash ./scripts/ci/update_homebrew_cask.sh \
  --dmg dist/macos/XWorkmate-1.2.0.dmg \
  --version 1.2.0 \
  --tag v1.2.0 \
  --dry-run
```
