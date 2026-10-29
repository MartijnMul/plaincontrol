PROJECT  := Plaincontrol.xcodeproj
SCHEME   := Plaincontrol
CORE     := Packages/PlaincontrolCore
DERIVED  := .build/DerivedData
DEV_APP  := $(DERIVED)/Build/Products/Debug/Plaincontrol Dev.app
HOOK     := plugin/bin/plaincontrol-hook
SCENARIO ?= sessions

# Development builds of the hook talk to the development app, never to the release app.
export PLAINCONTROL_SOCKET := $(HOME)/Library/Application Support/Plaincontrol Dev/hooks.sock

.DEFAULT_GOAL := help

.PHONY: help generate build test lint format check open run fresh demo demo-sessions hook simulate dev-claude release clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

generate: ## Generate the Xcode project from project.yml
	xcodegen generate --quiet

build: generate ## Build the development app
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination "platform=macOS" -derivedDataPath $(DERIVED) -quiet build

test: ## Run the core package tests, with this Mac's test values from .env
	set -a; [ ! -f .env ] || . ./.env; set +a; swift test --package-path $(CORE)

lint: ## Check formatting
	swift format lint --strict --recursive App $(CORE)

format: ## Format all Swift code
	swift format --in-place --recursive App $(CORE)

check: lint test build ## Run everything CI runs

open: generate ## Open the project in Xcode
	open $(PROJECT)

# Started with an empty environment, as from Finder: `open` passes its own on to the app, and
# the app to the terminals and editors it launches, so a run from inside a Claude Code session
# would hand that session's variables to every shell in them. The release app is quit too: both
# react to the same key for the launcher.
run: build ## Build and start the development app, quitting the release app
	-pkill -x "Plaincontrol Dev"
	-pkill -x Plaincontrol
	env -i open "$(DEV_APP)"

fresh: build ## Start the development app as on its first start (NEW=1: in an empty home folder)
	scripts/fresh-dev.sh "$(DEV_APP)"

demo: build ## Start the development app on invented projects, for screenshots
	DEMO=1 scripts/fresh-dev.sh "$(DEV_APP)"

# Sessions in the demo's projects, as from iTerm2 panes, so the menu can jump to them.
demo-sessions: hook ## Play invented sessions into the demo
	sed 's|__HOME__|/Users/Shared/plaincontrol-demo|g' dev/demo/sessions.jsonl >.build/demo-sessions.jsonl
	TERM_PROGRAM=iTerm.app __CFBundleIdentifier=com.googlecode.iterm2 \
		ITERM_SESSION_ID=w0t0p0:6B9F3C2A-0D4E-4F1A-9C8B-7E6D5A4B3C21 \
		dev/simulate.sh $(HOOK) .build/demo-sessions.jsonl 0.3

hook: ## Build the hook command into the plugin
	swift build --package-path $(CORE) -c release --product plaincontrol-hook
	mkdir -p plugin/bin
	cp "$$(swift build --package-path $(CORE) -c release --show-bin-path)/plaincontrol-hook" $(HOOK)

simulate: hook ## Play a scenario into the development app (SCENARIO=sessions|permission|question)
	dev/simulate.sh $(HOOK) dev/scenarios/$(SCENARIO).jsonl

dev-claude: hook ## Start Claude Code with this plugin, reporting to the development app
	claude --plugin-dir plugin

release: ## Build, sign and notarise a release disk image (see scripts/release.sh)
	scripts/release.sh

clean: ## Remove generated and built files
	rm -rf $(PROJECT) .build $(CORE)/.build plugin/bin
