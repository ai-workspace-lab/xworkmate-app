## Skills

- Use `xworkmate-secure-development` for any change that touches gateway auth, `.env`, secure storage, tokens, passwords, TLS, file upload, native entitlements, packaging, or release-sensitive settings.
- Use `xworkmate-acceptance` before claiming build, packaging, installation, or release readiness for this repo.
- For non-trivial implementation work, default to the repo skill `xworkmate-worktree-task-mode` and follow its worktree-first execution flow without asking the user to restate that preference each time.

## Default Task Mode

- Default to an isolated `git worktree` for non-trivial tasks. Create the worktree from `main`, do the work there, merge back to `main`, then remove the temporary worktree when done.
- Default to concurrent execution for independent sub-tasks. Keep the main agent on the critical path and use parallel lanes only for bounded side work that does not block the next local step.
- Do not repeatedly ask whether worktree mode or concurrent execution should be used for this repo; treat that as the default unless the user explicitly asks for a different flow.
- Keep the branch/worktree lifecycle explicit: inspect, implement, verify, merge, clean up.

## Security Rules

- `.env` is only a development/test prefill source for Settings -> Integrations -> Gateway. Do not hardcode `.env` values into source code. Do not auto-persist them into settings. Do not auto-connect from them.
- Secrets must not be committed, logged, screenshot-exposed, or stored in `SharedPreferences`. Use secure storage for persisted secrets.
- For a user-initiated gateway connect action, the current form values may be used directly for the immediate handshake. Do not require a secure-store readback for the active request.
- Keep network trust boundaries explicit. Loopback/local mode may use non-TLS intentionally; remote mode must not silently downgrade transport security.
- File and attachment access must be user-driven. Never read or send workspace files implicitly.
- Any new macOS or iOS entitlement must be least-privilege, justified by the feature, and covered by tests or manual verification notes.
- Auth, secret, network, or entitlement changes require `flutter analyze`, relevant unit/widget tests, and serial device-run integration tests when integration coverage is needed.

See [docs/security/secure-development-rules.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/security/secure-development-rules.md) for the full checklist.
