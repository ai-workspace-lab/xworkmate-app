.DEFAULT_GOAL := help

SHELL := /bin/bash

FLUTTER ?= flutter
PNPM ?= pnpm
DART ?= dart
DEVICE ?= macos
APP_STORE_DART_DEFINE ?= --dart-define=XWORKMATE_APP_STORE=true
PUBSPEC_VERSION_LINE := $(shell sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)
PUBSPEC_BUILD_DATE := $(shell sed -n 's/^build-date:[[:space:]]*//p' pubspec.yaml | head -n 1)
PUBSPEC_BUILD_ID := $(shell sed -n 's/^build-id:[[:space:]]*//p' pubspec.yaml | head -n 1)
APP_VERSION := $(firstword $(subst +, ,$(PUBSPEC_VERSION_LINE)))
APP_BUILD_NUMBER_RAW := $(word 2,$(subst +, ,$(PUBSPEC_VERSION_LINE)))
APP_BUILD_NUMBER := $(if $(APP_BUILD_NUMBER_RAW),$(APP_BUILD_NUMBER_RAW),1)
APP_DART_DEFINE_VERSION ?= --dart-define=XWORKMATE_DISPLAY_VERSION=$(APP_VERSION)
APP_DART_DEFINE_BUILD ?= --dart-define=XWORKMATE_BUILD_NUMBER=$(APP_BUILD_NUMBER)

.PHONY: help deps analyze test test-all test-flutter test-golden test-integration test-integration-macos test-patrol test-go test-ci check format run open-macos-xcode sync-version build-linux build-macos build-ios-sim package-deb package-rpm package-linux package-mac install-mac clean build-go-core render-release-docs check-export-compliance

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-18s %s\n", $$1, $$2}'

deps: ## Install Flutter dependencies
	$(FLUTTER) pub get

analyze: ## Run static analysis
	$(FLUTTER) analyze

test: ## Run Flutter tests
	$(FLUTTER) test

test-flutter: ## Run the full Flutter unit/widget test suite
	$(FLUTTER) test

test-golden: ## Run Flutter Golden tests
	$(FLUTTER) test test/golden

test-integration: ## Run Flutter integration tests
	$(FLUTTER) test integration_test

test-integration-macos: ## Run macOS integration tests serially for the desktop app
	$(FLUTTER) test integration_test/desktop_navigation_flow_test.dart -d macos
	$(FLUTTER) test integration_test/desktop_settings_flow_test.dart -d macos

test-patrol: ## Run Patrol end-to-end tests
	dart pub global activate patrol_cli
	patrol test

test-go: ## Run xworkmate-bridge Go unit tests
	cd ../xworkmate-bridge && go test ./...

test-ci: test-flutter test-golden test-integration test-go ## Run the PR validation chain

test-all: test-ci test-patrol ## Run the full local validation chain

check: analyze test ## Run the standard validation suite

format: ## Format Dart sources
	$(DART) format lib test

render-release-docs: ## Render feature matrix, roadmap, release notes, and changelog docs
	$(DART) run tool/render_release_docs.dart

sync-version: ## Show the version/build metadata sourced from pubspec.yaml
	@echo "version=$(APP_VERSION)"
	@echo "build=$(APP_BUILD_NUMBER)"
	@echo "build-date=$(PUBSPEC_BUILD_DATE)"
	@echo "build-id=$(PUBSPEC_BUILD_ID)"

run: ## Run the app on a device or desktop target (DEVICE=macos by default)
	$(FLUTTER) run -d $(DEVICE)

open-macos-xcode: ## Open the supported macOS Xcode workspace entrypoint
	open macos/Runner.xcworkspace

build-linux: ## Build the Linux app in release mode
	$(FLUTTER) build linux --release

build-macos: ## Build the macOS app in release mode
	$(FLUTTER) build macos --release $(APP_STORE_DART_DEFINE) --build-name=$(APP_VERSION) --build-number=$(APP_BUILD_NUMBER) $(APP_DART_DEFINE_VERSION) $(APP_DART_DEFINE_BUILD)
	bash scripts/check-apple-export-compliance.sh build/macos/Build/Products/Release/XWorkmate.app

build-ios-sim: ## Build the iOS app for the simulator
	$(FLUTTER) build ios --simulator $(APP_STORE_DART_DEFINE) --build-name=$(APP_VERSION) --build-number=$(APP_BUILD_NUMBER) $(APP_DART_DEFINE_VERSION) $(APP_DART_DEFINE_BUILD)
	bash scripts/check-apple-export-compliance.sh build/ios/iphonesimulator/Runner.app

build-go-core: ## Build the external ACP bridge helper from xworkmate-bridge
	bash scripts/build-go-core.sh

package-deb: ## Create the Linux .deb package
	bash scripts/package-linux-deb.sh

package-rpm: ## Create the Linux .rpm package
	bash scripts/package-linux-rpm.sh

package-linux: ## Create both Linux packages
	bash scripts/package-linux.sh

package-mac: ## Create the macOS .app and DMG
	XWORKMATE_APP_STORE=true bash scripts/package-flutter-mac-app.sh

install-mac: ## Package and install the macOS app into /Applications
	XWORKMATE_APP_STORE=true bash scripts/package-flutter-mac-app.sh
	bash scripts/install-flutter-mac-dmg.sh

clean: ## Remove generated artifacts
	$(FLUTTER) clean
	rm -rf build dist

check-export-compliance: ## Verify source and built Apple plist export-compliance flags
	bash scripts/check-apple-export-compliance.sh

# Rust FFI targets
.PHONY: rust-build rust-build-release rust-build-debug rust-test ffi-copy ffi-generate

rust-build: rust-build-release ## Build Rust FFI library (release mode)

rust-build-release: ## Build Rust FFI library for macOS (arm64)
	cd rust && cargo build --release --target aarch64-apple-darwin
	@echo "Rust FFI library built successfully"

rust-build-debug: ## Build Rust FFI library in debug mode
	cd rust && cargo build --target aarch64-apple-darwin

rust-test: ## Run Rust tests
	cd rust && cargo test

ffi-copy: ## Copy FFI library to macOS Frameworks
	bash scripts/copy_ffi_framework.sh

ffi-generate: ## Generate FFI bindings using flutter_rust_bridge
	bash scripts/generate_ffi_bindings.sh

ffi-integrate: rust-build-release ffi-copy ## Build and copy FFI library (full integration)

# Build with FFI integration
build-macos-ffi: rust-build-release ffi-copy build-macos ## Build macOS app with FFI integration
