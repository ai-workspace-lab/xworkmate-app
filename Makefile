.DEFAULT_GOAL := help

SHELL := /bin/bash

APP_NAME ?= XWorkmate
BUILD_SYSTEM_NAME ?= $(APP_NAME) Build System

FLUTTER ?= flutter
DART ?= dart
DEVICE ?= macos
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
ARCH ?= $(UNAME_M)

APP_STORE_DART_DEFINE ?= --dart-define=XWORKMATE_APP_STORE=true
PUBSPEC_VERSION_LINE := $(shell sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)
PUBSPEC_BUILD_DATE := $(shell sed -n 's/^build-date:[[:space:]]*//p' pubspec.yaml | head -n 1)
PUBSPEC_BUILD_ID := $(shell sed -n 's/^build-id:[[:space:]]*//p' pubspec.yaml | head -n 1)
APP_VERSION := $(firstword $(subst +, ,$(PUBSPEC_VERSION_LINE)))
APP_BUILD_NUMBER_RAW := $(word 2,$(subst +, ,$(PUBSPEC_VERSION_LINE)))
APP_BUILD_NUMBER := $(if $(APP_BUILD_NUMBER_RAW),$(APP_BUILD_NUMBER_RAW),1)
APP_BUILD_DATE := $(if $(PUBSPEC_BUILD_DATE),$(PUBSPEC_BUILD_DATE),unknown)
APP_BUILD_COMMIT := $(if $(PUBSPEC_BUILD_ID),$(PUBSPEC_BUILD_ID),unknown)

APP_DART_DEFINE_VERSION ?= --dart-define=XWORKMATE_DISPLAY_VERSION=$(APP_VERSION)
APP_DART_DEFINE_BUILD ?= --dart-define=XWORKMATE_BUILD_NUMBER=$(APP_BUILD_NUMBER)
APP_DART_DEFINE_BUILD_DATE ?= --dart-define=XWORKMATE_BUILD_DATE=$(APP_BUILD_DATE)
APP_DART_DEFINE_BUILD_COMMIT ?= --dart-define=XWORKMATE_BUILD_COMMIT=$(APP_BUILD_COMMIT)
DART_DEFINES := $(APP_DART_DEFINE_VERSION) $(APP_DART_DEFINE_BUILD) $(APP_DART_DEFINE_BUILD_DATE) $(APP_DART_DEFINE_BUILD_COMMIT)

.PHONY: help \
	package-mac build-macos-arm64 build-macos-x64 \
	build-windows-x64 build-linux-x64 build-ios-ipa \
	build-android-apk build-android-play \
	analyze format clean sync-macos-config dns-check dns-flush \
	test check run build-linux build-macos sync-version package-linux package-deb package-rpm

help:
	@echo "$(BUILD_SYSTEM_NAME)"
	@echo ""
	@echo "Usage: make <target> [ARCH=<arch>]"
	@echo ""
	@echo "Platform targets:"
	@echo "  package-mac        Build macOS release + DMG (native arch)"
	@echo "  build-macos-arm64   Build macOS ARM64 release + DMG"
	@echo "  build-macos-x64     Build macOS x64 release + DMG"
	@echo "  build-windows-x64   Build Windows x64 release"
	@echo "  build-linux-x64     Build Linux x64 release"
	@echo "  build-ios-ipa       Build iOS IPA (requires macOS)"
	@echo "  build-android-apk   Build Android APK and Play App Bundle"
	@echo "  build-android-play  Build and verify a Play-uploadable signed AAB"
	@echo ""
	@echo "Utility targets:"
	@echo "  analyze             Run Flutter static analysis"
	@echo "  format              Format Dart code"
	@echo "  clean               Clean build artifacts"
	@echo "  sync-macos-config   Sync pubspec.yaml version to macOS config"
	@echo "  dns-check           Diagnose DNS resolution and cache status"
	@echo "  dns-flush           Flush local system DNS cache (requires sudo)"

package-mac: ## Build macOS release + DMG (native arch)
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "This target requires macOS"; \
		exit 1; \
	fi
	ARCH="$(ARCH)" XWORKMATE_APP_STORE=true bash scripts/package-flutter-mac-app.sh

build-macos-arm64: ## Build macOS ARM64 release + DMG
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "This target requires macOS"; \
		exit 1; \
	fi
	$(MAKE) package-mac ARCH=arm64

build-macos-x64: ## Build macOS x64 release + DMG
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "This target requires macOS"; \
		exit 1; \
	fi
	$(MAKE) package-mac ARCH=x86_64

build-windows-x64: ## Build Windows x64 release
	$(FLUTTER) build windows --release $(DART_DEFINES)

build-linux-x64: ## Build Linux x64 release
	$(FLUTTER) build linux --release --build-name=$(APP_VERSION) --build-number=$(APP_BUILD_NUMBER) $(DART_DEFINES)

build-ios-ipa: ## Build iOS IPA (requires macOS)
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "This target requires macOS"; \
		exit 1; \
	fi
	bash scripts/package-ios-ipa.sh

build-android-apk: ## Build Android APK and Play App Bundle
	bash scripts/package-android-apk.sh

build-android-play: ## Build and verify a Play-uploadable signed AAB
	bash scripts/package-android-apk.sh
	bash scripts/verify-android-release.sh

analyze: ## Run Flutter static analysis
	$(FLUTTER) analyze

format: ## Format Dart code
	$(DART) format lib test

clean: ## Clean build artifacts
	@if command -v $(FLUTTER) >/dev/null 2>&1; then \
		$(FLUTTER) clean; \
	else \
		echo "flutter not found; skipping flutter clean"; \
	fi
	rm -rf build dist

sync-macos-config: ## Sync pubspec.yaml version to macOS config
	$(FLUTTER) build macos --config-only --build-name=$(APP_VERSION) --build-number=$(APP_BUILD_NUMBER) $(DART_DEFINES)
	@echo "version=$(APP_VERSION)"
	@echo "build=$(APP_BUILD_NUMBER)"
	@echo "build-date=$(PUBSPEC_BUILD_DATE)"
	@echo "build-id=$(PUBSPEC_BUILD_ID)"
	@if [ -f macos/Flutter/ephemeral/Flutter-Generated.xcconfig ]; then \
		sed -n 's/^FLUTTER_BUILD_NAME=/xcode-build-name=/p; s/^FLUTTER_BUILD_NUMBER=/xcode-build-number=/p' macos/Flutter/ephemeral/Flutter-Generated.xcconfig; \
	fi

dns-check: ## Diagnose DNS resolution and cache status
	@bash ./scripts/dns-check.sh

dns-flush: ## Flush local system DNS cache (requires sudo)
	@bash ./scripts/dns-flush.sh

test: ## Run Flutter tests
	$(FLUTTER) test

check: analyze test ## Run static analysis and tests

run: ## Run the app on a device or desktop target (DEVICE=macos by default)
	$(FLUTTER) run -d $(DEVICE)

# Convenience aliases
build-linux: build-linux-x64
build-macos: package-mac
sync-version: sync-macos-config
package-linux:
	bash scripts/package-linux.sh
package-deb:
	bash scripts/package-linux-deb.sh
package-rpm:
	bash scripts/package-linux-rpm.sh
