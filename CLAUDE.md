# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

CodexBar is a macOS 14+ (Sonoma) menu bar app monitoring AI coding tool usage across ~70 providers. Built with Swift 6 and strict concurrency, SwiftPM-only (no Xcode project). Fork of [steipete/CodexBar](https://github.com/steipete/CodexBar), synced to upstream 0.46.0.

The fork's only functional delta is **color-coded menu bar icons**, plus a disabled Sparkle feed and fork signing identity. Separator styles and session/weekly window selection were retired in the 0.46 sync — upstream's layout editor and `MenuBarMetricPreference` supersede them.

The tint feature is **entirely fork-only** — upstream has no `MenuBarUsageTint`, no `menuBarUsageColorsEnabled`, and no `tint:` parameter on `IconRenderer.makeIcon`. The fork carries the whole implementation and defaults it on; PR #24 is the attempt to upstream it, staged off `vendor/upstream-main` and defaulting to off. Do not assume any part of it exists upstream when resolving a sync conflict.

## Build, Test, Lint

**Build with Xcode's Swift, not swiftly's.** A swiftly-managed toolchain shadows `swift` on `PATH` and is Swift 6.2.3 built `+assertions`; it aborts the compiler in at least two unrelated places that Xcode's 6.3 compiles cleanly — an IRGen debug-type assertion in `StatusItemController+SwitcherViews.swift` (debug builds) and a SIL verifier failure in `CostUsageJsonl.scanBounded` (release builds, so `make package` and `make sign-and-release` too). Both are assertion-only checks a stock compiler never runs, and both sites are byte-identical to upstream. Upstream CI uses 6.3.x, which is why CI stays green on code that aborts locally.

```bash
# TOOLCHAINS=default does NOT work — swiftly's shim resolves the toolchain itself and ignores it.
export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH
swift --version   # must report 6.3 before building
```

Also: never run `swift test` / `Scripts/test.sh` while another build is using the same `.build` — the second process blocks on the SwiftPM lock and the sharded runner reports it as a group timeout (exit 124), which reads exactly like a real failure. Pass `--scratch-path` to isolate.

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift test                               # Full XCTest suite
swift test --filter TestClass/testMethod  # Single test

./Scripts/compile_and_run.sh             # Full dev cycle: kill → build → test → package → relaunch → verify
./Scripts/lint.sh lint                   # locales + portable checks + SwiftFormat + SwiftLint --strict
./Scripts/lint.sh lint-macos             # locales + SwiftFormat (what CI runs on macOS)
./Scripts/lint.sh lint-linux             # portable checks + SwiftLint (what CI runs on Linux)
./Scripts/lint.sh format                 # SwiftFormat auto-fix
node Scripts/check-app-locales.mjs       # locale completeness; new L() keys need all 23 catalogs
./Scripts/package_app.sh                 # Build release binary → create CodexBar.app bundle
./Scripts/sign-and-notarize.sh           # Code sign + notarize (arm64 zip)
./Scripts/make_appcast.sh <zip> <url>    # Generate Sparkle appcast
```

After code changes, always rebuild and restart via `./Scripts/compile_and_run.sh` before validating behavior.

## Architecture

### Provider System

Each provider lives in `Sources/CodexBarCore/Providers/<Name>/` with two files:
- **`*ProviderDescriptor`** — Metadata (display name, icon, color, supported source modes). Registered by hand in the `ProviderDescriptorRegistry.descriptorsByID` map in `Sources/CodexBarCore/Providers/ProviderDescriptor.swift`. Adding a provider means adding an entry there; a missing one trips a `preconditionFailure` at bootstrap.
- **`*StatusProbe`** — Fetch logic implementing one or more `ProviderFetchStrategy` variants (`.oauth`, `.web`, `.cli`, `.api`, `.localProbe`). Strategies declare availability and execute fetches with automatic fallback chaining.

### Data Flow

```
UsageFetcher (orchestrator)
  → ProviderFetchPlan (strategy selection per provider)
    → *StatusProbe.fetch() (tries strategies in order, falls back on error)
      → UsageSnapshot (primary/secondary/tertiary RateWindow, identity, credits)
        → UsageStore (@Observable, central state)
          → IconRenderer (18×18 pt template images with usage bars)
          → MenuCardView (detailed provider cards in dropdown)
          → StatusItemController (NSStatusItem management)
```

### Key Types

| Type | Location | Role |
|------|----------|------|
| `UsageFetcher` | `Sources/CodexBarCore/UsageFetcher.swift` | Orchestrates all provider fetches |
| `UsageStore` | `Sources/CodexBar/UsageStore.swift` | `@Observable` state container for all snapshots |
| `SettingsStore` | `Sources/CodexBar/SettingsStore.swift` | User preferences (`@Observable`) |
| `IconRenderer` | `Sources/CodexBar/IconRenderer.swift` | Renders menu bar icons with usage bars |
| `MenuCardView` | `Sources/CodexBar/MenuCardView.swift` | SwiftUI provider detail cards |
| `StatusItemController` | `Sources/CodexBar/StatusItemController.swift` | NSStatusItem lifecycle |
| `UsageSnapshot` | `Sources/CodexBarCore/` | Core output: rate windows, identity, cost |
| `RateWindow` | `Sources/CodexBarCore/` | Percentage used, window duration, reset time |
| `ConsecutiveFailureGate` | `Sources/CodexBarCore/` | Debounces flaky errors before displaying |


### Authentication Chain

Providers authenticate via a fallback chain configured in their descriptor's `supportedSourceModes`:
1. **OAuth** — Token from macOS Keychain (Claude, Codex, VertexAI). Claude defaults to `/usr/bin/security` CLI reader (avoids keychain prompts on rebuild); Security.framework available as user override.
2. **Web/Cookies** — Browser cookie extraction via SweetCookieKit (Cursor, Copilot, Gemini). Default to Chrome-only to avoid other browser prompts.
3. **CLI** — Parse stdout from CLI tools via PTY (Claude, Codex, Augment)
4. **API** — Direct API calls with stored token
5. **LocalProbe** — Parse local config/log files

## Code Style (enforced by SwiftFormat + SwiftLint)

- 4-space indent, 120-char max line width, LF line endings
- **Explicit `self` required** — do not remove; required for Swift 6 concurrency safety
- `@testable` imports grouped at bottom
- Type organization: `--organizetypes class,struct,enum,extension` with `MARK: - %t + %p` annotations
- Prefer `@Observable` / `@State` / `@Bindable` over `ObservableObject` / `@ObservedObject` / `@StateObject`
- Favor modern macOS 15+ APIs over deprecated counterparts
- Keep provider data siloed — never display identity/plan fields from a different provider
- Test naming: `FeatureNameTests` class with `test_caseDescription` methods

## Dependencies

| Package | Purpose |
|---------|---------|
| Sparkle | Auto-update framework |
| Commander | CLI argument parsing |
| swift-log | Logging infrastructure |
| swift-syntax | Macro implementation |
| KeyboardShortcuts | Global hotkey support |
| SweetCookieKit | Browser cookie extraction (can override to local path via `SWEETCOOKIEKIT_PATH` env var) |

## Fork Context

- **Upstream:** `steipete/CodexBar` — Augment is present upstream; nothing provider-related is fork-only
- **Secondary upstream:** `nguyenphutrong/quotio` — monitored for feature ideas
- **Fork-specific:** the entire color-icon feature (`MenuBarUsageTint.swift`, the `IconRenderer` tint path, `menuBarUsageColorsEnabled` defaulted on) — none of it exists upstream; Sparkle feed disabled in `Scripts/package_app.sh` (fork shares upstream's bundle ID *and* Sparkle key, so a live feed would auto-update fork installs into upstream builds); `APP_TEAM_ID`/signing identity
- **Local carry:** `StatusItemController+SwitcherViews.swift` passes the widths into `makeTitle()` instead of capturing the mutable `emailWidth`/`workspaceWidth` vars. This works around a *toolchain* bug, not a code defect — see the toolchain note above. Keep it (it costs nothing and unblocks anyone on 6.2.3), but do not treat it as evidence the source is wrong.
- **Upstream sync scripts:** `Scripts/check_upstreams.sh`, `Scripts/review_upstream.sh`, `Scripts/prepare_upstream_pr.sh`
- **Version:** Tracked in `version.env` (`MARKETING_VERSION` + `BUILD_NUMBER`)
