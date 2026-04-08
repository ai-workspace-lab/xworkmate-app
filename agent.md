# Agent Rules

- Do not run automated tests by default. Run tests only when the user explicitly asks for testing or verification.
- Add or update widget tests and golden tests for any Flutter UI page change.
- Add or update integration tests for any core business flow change.
- Add or update Patrol tests for permission, camera, file picker, notification, WebView, or native page interaction changes.
- Add or update Go `*_test.go` coverage for any handler, service, or repository change.
- Prefer `Key`-based locators for all UI automation.
- Keep tests modular and split by feature.
- Do not update golden baselines without UI review confirmation.
- Fix failing tests or implementation directly; do not skip CI failures.
