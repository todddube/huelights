# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

HueBar: a native macOS menu bar app (SwiftUI `MenuBarExtra`, `.window` style) that discovers,
pairs with and controls Philips Hue bridges. Swift 6 language mode with strict concurrency.
The previous Python/Streamlit implementation lives untouched in `backup/` (git-ignored).

## Layout

- `HueKit/` — UI-free Swift package. `HueClient` (actor) speaks CLIP v2 over HTTPS plus the
  few v1 endpoints that have no v2 equivalent (firmware, light search, bridge rename).
  `HueDiscovery` does Bonjour → IPv4 resolution, cloud fallback and `/api/0/config` probing.
  `BridgeTrustDelegate` pins the bridge certificate (TOFU, common name must equal the bridge id).
  `HueColor` converts sRGB ↔ CIE xy with gamut clamping. Tests in `HueKit/Tests`.
- `HueBar/` — the app. `Store/BridgeStore` is the single `@MainActor @Observable` model;
  views never call `HueClient` directly. `Store/PairedBridge` persists credentials to
  `~/Library/Application Support/HueBar/bridges.json` (deliberately not the keychain, see its
  doc comment). `Views/` are small SwiftUI views; `Views/Controls.swift` holds shared pieces.
- `project.yml` → `HueBar.xcodeproj` via xcodegen. `Package.swift` builds the same sources
  with SwiftPM; `scripts/build-app.sh` wraps the binary into `build/HueBar.app`.
- `scripts/make-icons.swift` renders the icon set, `.icns` and logo; `HueBar/Views/HueLogo.swift`
  draws the same mark in SwiftUI.

## Commands

```bash
make build / make app / make run / make install
make test                 # HueKit tests, then HueBarTests (swift test at the root)
HUEBAR_LIVE=1 make test   # opt-in tests against the real bridge on the LAN
make xcodeproj            # after adding/removing files outside Xcode
make icons                # re-render artwork
xcodebuild -project HueBar.xcodeproj -scheme HueBar build
```

## Testing

- App tests live in `HueBarTests/` and run through SwiftPM only (not in the Xcode scheme).
- Tests must pass a temporary directory to `BridgeStore(credentialsDirectory:)` and
  `PairedBridge.load/save/clear`; never touch `~/Library/Application Support/HueBar`.

## Conventions

- Follow `~/.claude/swift-standards.md` (file headers with target `HueKit · HueBar` or
  `HueBar · HueBar`, `///` docs, `os.Logger`, no `try!`/force unwraps on input).
- Writes to the bridge go through `BridgeStore.send(key:delay:_:)`, which coalesces slider
  drags per resource and suppresses incoming events for that resource while a write is pending.
- Every bridge write passes `transitionMilliseconds` from the store.
- New CLIP v2 fields: add them as optionals on the model and on `HueEventResource` so the
  event stream can apply partial updates.
- Keep the app unsandboxed: sandboxing would move the credentials file into a container and
  break sharing with `swift run`.
