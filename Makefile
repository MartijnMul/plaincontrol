PROJECT := Plaincontrol.xcodeproj
SCHEME  := Plaincontrol
CORE    := Packages/PlaincontrolCore
DERIVED := .build/DerivedData

.DEFAULT_GOAL := help

.PHONY: help generate build test lint format check open run clean

help: ## List the available commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

generate: ## Generate the Xcode project from project.yml
	xcodegen generate --quiet

build: generate ## Build the app
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "platform=macOS" -derivedDataPath $(DERIVED) -quiet build

test: ## Run the core package tests
	swift test --package-path $(CORE)

lint: ## Check formatting
	swift format lint --strict --recursive App $(CORE)

format: ## Format all Swift code
	swift format --in-place --recursive App $(CORE)

check: lint test build ## Run everything CI runs

open: generate ## Open the project in Xcode
	open $(PROJECT)

run: build ## Build and start the app
	open $(DERIVED)/Build/Products/Debug/Plaincontrol.app

clean: ## Remove generated and built files
	rm -rf $(PROJECT) .build $(CORE)/.build
