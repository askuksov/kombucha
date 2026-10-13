# Shortcuts for the commands in README.md. Run `make help` for the list.

APP         := build/DerivedData/Build/Products/Release/Kombucha.app
XCODE_26    := /Applications/Xcode-26.app/Contents/Developer
DEV_TEAM    := $(shell sed -n 's/^KOMBUCHA_TEAM = //p' Config/Shared.xcconfig)

# Command Line Tools cannot build this project. Use Xcode 26 when it sits at the usual side-by-side path.
ifeq ($(origin DEVELOPER_DIR),undefined)
ifneq ($(wildcard $(XCODE_26)),)
export DEVELOPER_DIR := $(XCODE_26)
endif
endif

.DEFAULT_GOAL := help
.PHONY: help generate build verify install test test-kit test-app release release-dry clean

help: ## Show this list
	@awk -F ':.*## ' '/^[a-zA-Z_-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Release needs the team: make release TEAM=ABCDE12345"

generate: ## Generate Kombucha.xcodeproj with XcodeGen
	xcodegen generate

build: generate ## Build Release into build/DerivedData (signed with the team in Config)
	xcodebuild -project Kombucha.xcodeproj -scheme Kombucha -configuration Release \
		-derivedDataPath build/DerivedData build

verify: ## Check the signature shape of the built app
	scripts/verify-signature.sh $(APP)

install: build verify ## Build, quit the running app and install into /Applications
	-osascript -e 'tell application "Kombucha" to quit'
	@sleep 2
	ditto $(APP) /Applications/Kombucha.app
	@echo "Installed. Launch it from Launchpad or Spotlight."

test-kit: ## Run the KombuchaKit package tests
	xcrun swift test --package-path Packages/KombuchaKit

test-app: generate ## Run KombuchaTests (builds and launches the app as the test host)
	xcodebuild -scheme Kombucha -configuration Debug -derivedDataPath build/DerivedData \
		-destination 'platform=macOS,arch=arm64' test

test: test-kit test-app ## Run all tests

release: ## Sign with Developer ID, notarize and zip: make release TEAM=<team ID>
	@test -n "$(TEAM)" || { echo "usage: make release TEAM=ABCDE12345" >&2; exit 2; }
	scripts/release.sh --team $(TEAM) $(ARGS)

release-dry: ## Rehearse the release with the local Apple Development identity (no notarization)
	scripts/release.sh --team $(DEV_TEAM) --identity "Apple Development" --no-notarize --allow-dirty

clean: ## Remove build/, dist/ and the package build folder
	rm -rf build dist Packages/KombuchaKit/.build
