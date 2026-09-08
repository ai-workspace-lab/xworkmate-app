# Signing Key & Vault Provisioning Guide

Everything the Linux publishing lanes read out of HashiCorp Vault, and how to
put it there.

---

## 1. The secret path

`.github/workflows/build-and-release.yml` authenticates to Vault with the JWT
method (role `github-actions-xworkmate-app`) and reads every field from:

```
kv/data/github-actions/xworkmate-app
```

| Field | Used by | Required |
| :--- | :--- | :--- |
| `GPG_PRIVATE_KEY` | Launchpad PPA | Yes, to publish to the PPA |
| `GPG_KEY_ID` | Launchpad PPA | Yes, to publish to the PPA |
| `GPG_PASSPHRASE` | Launchpad PPA | Only if the signing key is passphrase-protected |
| `OBS_USERNAME` | Open Build Service | Yes, to upload new sources to OBS |
| `OBS_PASSWORD` | Open Build Service | Yes, to upload new sources to OBS |
| `OBS_TOKEN` | Open Build Service | Only for the trigger-only fallback |

Missing optional fields are tolerated (`ignoreNotFound: true`). Missing
*required* fields fail the publishing job rather than silently skipping it.

---

## 2. Generating the Launchpad signing key

Check for an existing key first:

```bash
gpg --list-secret-keys --keyid-format LONG
```

```text
sec   rsa4096/3AA45C1A2B3C4D5E 2026-07-22 [SC]
      8E419B2D1C3A5F7E9B0C1D2E3AA45C1A2B3C4D5E
uid                 [ultimate] Haitao Pan <haitaopanhq@gmail.com>
```

Here `GPG_KEY_ID` is `3AA45C1A2B3C4D5E` and the fingerprint is the long hex
string. To create one instead:

```bash
gpg --full-generate-key   # RSA and RSA, 4096 bits, no expiry
```

The email **must** be an address registered on the Launchpad account that
uploads to the PPA.

---

## 3. Registering the key with Launchpad

```bash
gpg --keyserver keyserver.ubuntu.com --send-keys <GPG_KEY_ID>
```

1. Open `https://launchpad.net/~<your-username>/+editpgpkeys`.
2. Paste the full fingerprint and click **Import Key**.
3. Launchpad emails an encrypted confirmation; decrypt it with
   `gpg --decrypt verification_email.txt` and open the link inside.
4. Confirm that account has upload rights to `ppa:ai-workspace-lab/ppa`.

Launchpad rejects any upload signed by a key it does not know, so this step is
what makes the PPA lane work at all.

---

## 4. Exporting the key for Vault

```bash
export GPG_PRIVATE_KEY_BASE64="$(gpg --export-secret-keys --armor <GPG_KEY_ID> | base64 | tr -d '\n')"
```

`publish_launchpad_ppa.sh` imports this into a throwaway `GNUPGHOME`, marks it
ultimately trusted, and deletes it when the job ends. A passphrase-protected key
works as long as `GPG_PASSPHRASE` is also provisioned; the script configures
loopback pinentry so `debsign` never blocks on a prompt.

---

## 5. Writing the secret

`vault kv put` replaces the whole secret, so pass every field you want to keep:

```bash
vault kv put -mount="kv" github-actions/xworkmate-app \
  GPG_KEY_ID="<GPG_KEY_ID>" \
  GPG_PRIVATE_KEY="$GPG_PRIVATE_KEY_BASE64" \
  GPG_PASSPHRASE="<passphrase or omit>" \
  OBS_USERNAME="<obs user>" \
  OBS_PASSWORD="<obs password>" \
  OBS_TOKEN="<obs token, optional>"
```

To add fields without disturbing the Apple/Windows/Android signing material that
lives at the same path, use `vault kv patch` instead:

```bash
vault kv patch -mount="kv" github-actions/xworkmate-app \
  OBS_USERNAME="<obs user>" OBS_PASSWORD="<obs password>"
```

Verify:

```bash
vault kv get -mount="kv" github-actions/xworkmate-app
```

---

## 6. How the workflow consumes them

```yaml
      - name: Load Vault secrets (Linux PPA GPG)
        id: vault_gpg
        uses: hashicorp/vault-action@v4
        with:
          url: ${{ env.VAULT_ADDR }}
          method: jwt
          role: github-actions-xworkmate-app
          jwtGithubAudience: vault
          ignoreNotFound: true
          secrets: |
            kv/data/github-actions/xworkmate-app GPG_PRIVATE_KEY | GPG_PRIVATE_KEY ;
            kv/data/github-actions/xworkmate-app GPG_KEY_ID | GPG_KEY_ID ;
            kv/data/github-actions/xworkmate-app GPG_PASSPHRASE | GPG_PASSPHRASE

      - name: Publish to Launchpad PPA
        uses: ./.github/actions/publish-launchpad-ppa
        with:
          gpg-private-key: ${{ steps.vault_gpg.outputs.GPG_PRIVATE_KEY }}
          gpg-key-id: ${{ steps.vault_gpg.outputs.GPG_KEY_ID }}
          gpg-passphrase: ${{ steps.vault_gpg.outputs.GPG_PASSPHRASE }}
          ppa-target: "ppa:ai-workspace-lab/ppa"
          source-dir: dist/ppa
```

See the [Launchpad PPA guide](launchpad-ppa-guide.md) and the
[OBS guide](obs-rpm-guide.md) for what each lane does with these secrets.
