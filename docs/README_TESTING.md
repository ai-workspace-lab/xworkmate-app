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
cd go_service
go test ./...
```

## CI Coverage

- Pull requests run Flutter tests, golden tests, integration tests, and Go tests.
- `release/*` branches run Patrol tests in addition to the PR chain.
