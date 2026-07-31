# CodexBar Makefile — thin wrappers around Scripts/*.sh
# Run `make` or `make help` to see available targets.

# Pull version from version.env for targets that need it
include version.env

# Matches codexbar_release_arch_label in Scripts/release_artifacts.sh.
ARCH_LABEL ?= macos-universal
export MARKETING_VERSION
export BUILD_NUMBER

# Auto-detect Developer ID signing identity to avoid keychain prompts on rebuild.
# Override: make run APP_IDENTITY="Developer ID Application: Your Name (TEAMID)"
APP_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
export APP_IDENTITY

# GitHub repo for fork releases (override: make sign-and-release GH_REPO="org/repo")
GH_REPO ?= johnlarkin1/CodexBar

.PHONY: help build build-release test run run-test lint format check \
        sign package release sign-and-release appcast check-release \
        validate-changelog check-upstream clean

# ── Default ──────────────────────────────────────────────────────────
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile | \
		awk -F ':.*## ' '{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Core Development ────────────────────────────────────────────────
build: ## Debug build
	swift build

build-release: ## Release build
	swift build -c release

test: ## Run full test suite
	swift test

run: ## Build, package, and launch (main dev workflow)
	./Scripts/compile_and_run.sh

run-test: ## Build with tests, package, and launch
	./Scripts/compile_and_run.sh --test

# ── Code Quality ────────────────────────────────────────────────────
check: lint ## Alias for lint (upstream tooling and AGENTS.md expect `make check`)

lint: ## SwiftFormat --lint + SwiftLint --strict (check only)
	./Scripts/lint.sh lint

format: ## SwiftFormat auto-fix
	./Scripts/lint.sh format

# ── Release ─────────────────────────────────────────────────────────
sign: ## Sign + notarize for distribution
	./Scripts/sign-and-notarize.sh

package: ## Build release binary and create CodexBar.app bundle
	./Scripts/package_app.sh

release: ## Full release pipeline (DISABLED — use sign-and-release instead)
	@echo "ERROR: 'make release' is disabled to prevent accidental pushes to upstream (steipete/CodexBar)." >&2; \
	echo "Use 'make sign-and-release' to release to $(GH_REPO)." >&2; \
	exit 1

_guard-no-upstream: ## (internal) Block releases targeting upstream
	@if echo "$(GH_REPO)" | grep -qi 'steipete/CodexBar'; then \
		echo "ERROR: Refusing to release to upstream steipete/CodexBar. Set GH_REPO to your fork." >&2; \
		exit 1; \
	fi

sign-and-release: _guard-no-upstream sign ## Sign, notarize, tag, and create GitHub release on fork
	@TAG="v$(MARKETING_VERSION)"; \
	ZIP="CodexBar-$(ARCH_LABEL)-$(MARKETING_VERSION).zip"; \
	DSYM_ZIP="CodexBar-$(ARCH_LABEL)-$(MARKETING_VERSION).dSYM.zip"; \
	if [ ! -f "$$ZIP" ]; then \
		echo "ERROR: $$ZIP not found. Did sign-and-notarize.sh succeed?" >&2; \
		exit 1; \
	fi; \
	echo "Tagging $$TAG and pushing to $(GH_REPO)..."; \
	git tag -f "$$TAG"; \
	git push -f origin "$$TAG"; \
	echo "Creating GitHub release on $(GH_REPO)..."; \
	NOTES="CodexBar $(MARKETING_VERSION) (build $(BUILD_NUMBER))"; \
	if [ -f CHANGELOG.md ]; then \
		SECTION=$$(awk '/^## \[?$(MARKETING_VERSION)\]?/{found=1;next} /^## /{if(found)exit} found' CHANGELOG.md); \
		if [ -n "$$SECTION" ]; then NOTES="$$SECTION"; fi; \
	fi; \
	gh release create "$$TAG" "$$ZIP" "$$DSYM_ZIP" \
		--repo "$(GH_REPO)" \
		--title "CodexBar $(MARKETING_VERSION)" \
		--notes "$$NOTES"; \
	echo "Release $(MARKETING_VERSION) published to $(GH_REPO)."

appcast: ## Generate Sparkle appcast (requires args: make appcast ARGS="<zip> <url>")
	@if [ -z "$(ARGS)" ]; then \
		echo "Usage: make appcast ARGS=\"<path-to-zip> <download-url>\""; \
		echo "  e.g. make appcast ARGS=\"CodexBar-0.18.0.zip https://example.com/CodexBar-0.18.0.zip\""; \
		exit 1; \
	fi
	./Scripts/make_appcast.sh $(ARGS)

# ── Validation & Checks ────────────────────────────────────────────
check-release: ## Verify GitHub release assets
	./Scripts/check-release-assets.sh

validate-changelog: ## Validate CHANGELOG.md for current version
	./Scripts/validate_changelog.sh $(MARKETING_VERSION)

check-upstream: ## Check upstream repos for changes
	./Scripts/check_upstreams.sh

# ── Utilities ───────────────────────────────────────────────────────
clean: ## Clean build artifacts
	rm -rf .build CodexBar.app
