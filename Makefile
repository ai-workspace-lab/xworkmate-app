.DEFAULT_GOAL := help

SHELL := /bin/bash

FLUTTER ?= flutter
PNPM ?= pnpm
DART ?= dart
DEVICE ?= macos

.PHONY: help deps analyze test check format run build-macos build-ios-sim package-mac install-mac clean

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

run: ## Run the app on a device or desktop target (DEVICE=macos by default)
	$(FLUTTER) run -d $(DEVICE)

build-macos: ## Build the macOS app in release mode
	$(FLUTTER) build macos --release

build-ios-sim: ## Build the iOS app for the simulator
	$(FLUTTER) build ios --simulator

package-mac: ## Create the macOS .app and DMG
	bash scripts/package-flutter-mac-app.sh

install-mac: ## Package and install the macOS app into /Applications
	bash scripts/package-flutter-mac-app.sh
	bash scripts/install-flutter-mac-dmg.sh

clean: ## Remove generated artifacts
	$(FLUTTER) clean
	rm -rf build dist
