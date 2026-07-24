# GPG Key Generation, Launchpad Import, and Vault Provisioning Guide

This guide provides step-by-step instructions for generating GPG keys, uploading public keys to Ubuntu keyserver and Launchpad, exporting Base64-encoded private keys, and storing `GPG_PRIVATE_KEY` and `GPG_KEY_ID` into HashiCorp Vault (`kv/data/github-actions/xworkmate-app`) for automated GitHub Actions PPA releases.

---

## 1. Overview of GPG Key Secrets

| Secret Key Name | Format / Example | Description |
| :--- | :--- | :--- |
| `GPG_KEY_ID` | `3AA45C1A2B3C4D5E` | 16-character hexadecimal GPG key identifier |
| `GPG_PRIVATE_KEY` | `LS0tLS1CRUdJTiBQR1...` | Base64-encoded ASCII-armored GPG private key |

---

## 2. Step 1: Generate or Locate GPG Key

### Option A: Check for an existing GPG key
```bash
gpg --list-secret-keys --keyid-format LONG
```
Output example:
```text
sec   rsa4096/3AA45C1A2B3C4D5E 2026-07-22 [SC]
      8E419B2D1C3A5F7E9B0C1D2E3AA45C1A2B3C4D5E
uid                 [ultimate] Haitao Pan <haitaopanhq@gmail.com>
```
In this example:
- **`GPG_KEY_ID`**: `3AA45C1A2B3C4D5E`
- **Fingerprint**: `8E419B2D1C3A5F7E9B0C1D2E3AA45C1A2B3C4D5E`

### Option B: Generate a new 4096-bit RSA GPG Key
If you do not have a GPG key:
```bash
gpg --full-generate-key
```
Select:
1. Key type: **(1) RSA and RSA**
2. Key size: **4096**
3. Expiration: **0** (does not expire)
4. Name: Your Name (e.g., `Haitao Pan`)
5. Email: Must match the email address registered on your Launchpad account!

---

## 3. Step 2: Publish Public Key to Ubuntu Keyserver & Launchpad

Launchpad requires public GPG keys to be registered on the official Ubuntu keyserver and validated on your Launchpad profile:

### 1. Send Public Key to Ubuntu Keyserver
```bash
gpg --keyserver keyserver.ubuntu.com --send-keys <GPG_KEY_ID>
```

### 2. Import Fingerprint into Launchpad
1. Visit `https://launchpad.net/~<your-username>/+editpgpkeys`.
2. Copy and paste your full **Fingerprint** (e.g. `8E419B2D1C3A5F7E9B0C1D2E3AA45C1A2B3C4D5E`).
3. Click **Import Key**.
4. Launchpad will send an encrypted verification email to your address.
5. Decrypt the email payload in your terminal:
   ```bash
   gpg --decrypt verification_email.txt
   ```
6. Open the confirmation link contained in the decrypted email to complete activation.

---

## 4. Step 3: Export Private Key for Vault

Export the ASCII-armored private key and convert it to a single-line Base64 string for Vault:

```bash
# Export and Base64-encode private key
export GPG_PRIVATE_KEY_BASE64=$(gpg --export-secret-keys --armor <GPG_KEY_ID> | base64 | tr -d '\n')

# Verify the Base64 output is non-empty
echo "$GPG_PRIVATE_KEY_BASE64" | head -c 50
```

---

## 5. Step 4: Provision Secrets into HashiCorp Vault

Store `GPG_PRIVATE_KEY` and `GPG_KEY_ID` under the `kv` mount at path `github-actions/xworkmate-app` (`/v1/kv/data/github-actions/xworkmate-app`):

```bash
# Using Vault CLI (preserving existing OBS_TOKEN)
vault kv put -mount="kv" github-actions/xworkmate-app \
  OBS_TOKEN="<your_obs_token>" \
  GPG_KEY_ID="<GPG_KEY_ID>" \
  GPG_PRIVATE_KEY="$GPG_PRIVATE_KEY_BASE64"
```

### Verification in Vault:
```bash
vault kv get -mount="kv" github-actions/xworkmate-app
```

---

## 6. How GitHub Actions Consumes the Secrets

In `.github/workflows/build-and-release.yml`, the workflow uses `hashicorp/vault-action@v4` with JWT mode to fetch these secrets:

```yaml
      - name: Load Vault secrets (Linux OBS & PPA)
        id: vault_linux
        uses: hashicorp/vault-action@v4
        with:
          url: ${{ env.VAULT_ADDR }}
          method: jwt
          role: github-actions-xworkmate-app
          secrets: |
            kv/data/github-actions/xworkmate-app OBS_TOKEN | OBS_TOKEN ;
            kv/data/github-actions/xworkmate-app GPG_PRIVATE_KEY | GPG_PRIVATE_KEY ;
            kv/data/github-actions/xworkmate-app GPG_KEY_ID | GPG_KEY_ID

      - name: Publish to Launchpad PPA
        run: bash ./scripts/ci/publish_launchpad_ppa.sh "${{ steps.vault_linux.outputs.GPG_PRIVATE_KEY }}" "${{ steps.vault_linux.outputs.GPG_KEY_ID }}" "ppa:ai-workspace-lab/ppa"
```
