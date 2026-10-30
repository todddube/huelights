# HueBar Swift Standards (project)

Project-specific rules for the `swift-code-reviewer` agent. These win over
`~/.claude/swift-standards.md` on conflict.

Last verified: 2026-10-30

## Platform baseline

| Item | Value |
|---|---|
| Toolchain | Apple Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| swift-tools-version | 6.0 (`Package.swift`, `HueKit/Package.swift`) |
| Language mode | Swift 6, `SWIFT_STRICT_CONCURRENCY = complete` |
| Deployment target | macOS 14.0 (SwiftPM `.macOS(.v14)`, project.yml, `LSMinimumSystemVersion`) |
| Targets | `HueBar` (executable / app, SwiftUI `MenuBarExtra`), `HueKit` (library), `HueKitTests` |
| Xcode project | Generated from `project.yml` with xcodegen (`make xcodeproj`); regenerate after adding/removing files |
| Signing | Ad-hoc (`CODE_SIGN_IDENTITY = -`), hardened runtime on, App Sandbox off |
| Tests | swift-testing; `HUEBAR_LIVE=1` enables live tests against a LAN bridge |

## Header target labels

| Path | Line 3 label |
|---|---|
| `HueKit/Sources/HueKit/` | `HueKit · HueBar` |
| `HueKit/Tests/HueKitTests/` | `HueKitTests · HueBar` |
| `HueBar/` (App, Store, Views) | `HueBar · HueBar` |
| `scripts/*.swift` | `scripts · HueBar` (shebang above the header) |

`Package.swift` files use a prose `//` block after `// swift-tools-version:`.

## Conventions observed

- Header format matches the global baseline (U+00B7 separator, summary ending in a period).
- `// MARK: - Section` in multi-concern files; `// MARK: Name` (no dash) used for
  property groups inside `BridgeStore`.
- Loggers: `Logger(subsystem: "com.todddube.HueBar", category: ...)`; network
  addresses logged `.public`.
- British spelling in prose and UI strings ("colour"), but API names use `color`.
- `@Observable @MainActor final class BridgeStore` is the single UI model, injected
  with `.environment(store)`.

## Deliberate decisions (do not flag)

- Credentials live in a `0600` JSON file under `~/Library/Application Support/HueBar`,
  not the keychain, so ad-hoc rebuilds and `swift run` share them (see `PairedBridge`).
- `BridgeTrustDelegate` uses trust-on-first-use pinning with a common-name check;
  `.permissive` is only for the unauthenticated `/api/0/config` probe.
- The app is unsandboxed and ad-hoc signed.

## Commands to avoid

- `make install` / `scripts/build-app.sh --install` (writes to /Applications).
- `make run` (kills and relaunches the user's running HueBar).
- Live tests are allowed only with the caller's consent; they must not change bridge state.

## Changes

- 2026-10-30 — Created from the initial Swift 6 rewrite (HueKit + HueBar).
