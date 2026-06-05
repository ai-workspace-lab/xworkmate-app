# Testing Guide

## Flutter

Run unit and widget tests:

```bash
flutter test
```

Run integration tests when the `integration_test` directory exists and contains integration test files:

```bash
flutter test integration_test
```

## Patrol

Run Patrol tests when `patrol_test/` exists and contains `*_test.dart` files:

```bash
make test-patrol
```

## Go

Run Go unit tests:

```bash
cd ../xworkmate-bridge
go test ./...
```

## CI Coverage

- Pull requests in `xworkmate-app` use the `verify` stage as a static-analysis gate and always run `flutter analyze`.
- Static analysis also runs `scripts/check-no-app-ffi.sh` so app packaging cannot reintroduce the retired Codex FFI copy/embed path.
- Widget, integration, and Patrol suites are owned by their dedicated commands and release validation flows, not by the lightweight `verify` gate.
- Pushes to `main`, version tags, and manual workflow runs publish build artifacts and update the GitHub Release entry for that release mode.
- `xworkmate-bridge` Go tests run in the companion repository.
- `release/*` branches run Patrol tests in addition to the PR chain when Patrol tests are present.
