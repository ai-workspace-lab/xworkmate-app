.DEFAULT_GOAL := help

SHELL := /bin/bash

FLUTTER ?= flutter
PNPM ?= pnpm
DART ?= dart
DEVICE ?= macos
APP_STORE_DART_DEFINE ?= --dart-define=XWORKMATE_APP_STORE=true

.PHONY: help deps analyze test check format run build-linux build-macos build-ios-sim package-deb package-rpm package-linux package-mac install-mac clean build-aris-bridge render-release-docs

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-18s %s\n", $$1, $$2}'

deps: ## Install Flutter dependencies
	$(FLUTTER) pub get

analyze: ## Run static analysis
	$(FLUTTER) analyze

test: ## Run Flutter tests
	$(FLUTTER) test

check: analyze test ## Run the standard validation suite

format: ## Format Dart sources
	$(DART) format lib test

render-release-docs: ## Render feature matrix, roadmap, release notes, and changelog docs
	$(DART) run tool/render_release_docs.dart

run: ## Run the app on a device or desktop target (DEVICE=macos by default)
	$(FLUTTER) run -d $(DEVICE)

build-linux: ## Build the Linux app in release mode
	$(FLUTTER) build linux --release

build-macos: ## Build the macOS app in release mode
	$(FLUTTER) build macos --release $(APP_STORE_DART_DEFINE)

build-ios-sim: ## Build the iOS app for the simulator
	$(FLUTTER) build ios --simulator $(APP_STORE_DART_DEFINE)

build-aris-bridge: ## Build the ARIS Go bridge helper
	bash scripts/build-aris-bridge.sh

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
