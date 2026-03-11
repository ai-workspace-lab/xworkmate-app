## Skills

- Use `xworkmate-secure-development` for any change that touches gateway auth, `.env`, secure storage, tokens, passwords, TLS, file upload, native entitlements, packaging, or release-sensitive settings.
- Use `xworkmate-acceptance` before claiming build, packaging, installation, or release readiness for this repo.

## Security Rules

- `.env` is only a development/test prefill source for Settings -> Integrations -> Gateway. Do not hardcode `.env` values into source code. Do not auto-persist them into settings. Do not auto-connect from them.
- Secrets must not be committed, logged, screenshot-exposed, or stored in `SharedPreferences`. Use secure storage for persisted secrets.
- For a user-initiated gateway connect action, the current form values may be used directly for the immediate handshake. Do not require a secure-store readback for the active request.
- Keep network trust boundaries explicit. Loopback/local mode may use non-TLS intentionally; remote mode must not silently downgrade transport security.
- File and attachment access must be user-driven. Never read or send workspace files implicitly.
- Any new macOS or iOS entitlement must be least-privilege, justified by the feature, and covered by tests or manual verification notes.
- Auth, secret, network, or entitlement changes require `flutter analyze`, relevant unit/widget tests, and serial device-run integration tests when integration coverage is needed.

See [docs/security/secure-development-rules.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/security/secure-development-rules.md) for the full checklist.
