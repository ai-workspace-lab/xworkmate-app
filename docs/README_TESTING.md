# Testing Guide

## Flutter

Run unit and widget tests:

```bash
flutter test
```

Run golden tests:

```bash
flutter test test/golden
```

Run integration tests:

```bash
flutter test integration_test
```

## Patrol

Run Patrol tests:

```bash
patrol test
```

## Go

Run Go unit tests:

```bash
cd ../xworkmate-bridge
go test ./...
```

## CI Coverage

- Pull requests in `xworkmate-app` run Flutter tests, golden tests, and integration tests.
- `xworkmate-bridge` Go tests run in the companion repository.
- `release/*` branches run Patrol tests in addition to the PR chain.
