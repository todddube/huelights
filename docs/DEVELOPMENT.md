# HueBar development guide

## Requirements

- macOS 14+ to run; Xcode 26 / Swift 6.x to build.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) only if you add or remove files
  (`brew install xcodegen`).
- A Hue bridge on the LAN for manual testing. Unit tests need none.

## Building and running

| Command | Does |
|---|---|
| `swift build` | Debug build of the app and HueKit |
| `swift run` | Run without a bundle (still no Dock icon) |
| `make app` | Release build → `build/HueBar.app`, ad-hoc signed |
| `make run` | Build, **kill any running HueBar**, relaunch |
| `make install` | Copy to `/Applications` |
| `make xcodeproj` | Regenerate `HueBar.xcodeproj` from `project.yml` |
| `make icons` | Re-render the icon set and logo |
| `xcodebuild -project HueBar.xcodeproj -scheme HueBar build` | Xcode build from the terminal |

To try the first-run flow without touching your real pairing, point the app at an empty folder:

```bash
HUEBAR_CONFIG_DIR=$(mktemp -d) swift run
```

## Architecture

```
AppDelegate ─ StatusItemController (NSStatusItem + NSPopover)
                    └─ NSHostingController ─ RootView ─ SetupView | ControlPanelView
                                                 ▲ environment
                                           BridgeStore (@MainActor @Observable)
                                                 │ async calls
                                            HueKit.HueClient (actor) ── CLIP v2 HTTPS + SSE
```

- **HueKit** is UI-free: models, `HueDiscovery` (Bonjour, cloud, `/api/0/config` probe),
  `HueClient`, certificate pinning (`BridgeTrustDelegate`) and `HueColor` (sRGB ↔ CIE xy).
- **BridgeStore** is the only model the views see. Writes go through `send(key:delay:_:)`, which
  coalesces slider drags per resource and ignores incoming events for that resource while a
  write is pending. Every write carries `transitionMilliseconds`.
- **Connection lifecycle:** `connect()` loads state and starts the event stream; if the bridge
  is unreachable it rediscovers it by id once (DHCP changes). `resync()` runs when the popover
  opens and shortly after wake.
- **Popover sizing:** the hosting controller publishes `preferredContentSize`, so the popup
  grows and shrinks with its content (`MenuBarExtra` cannot shrink).
- New CLIP v2 fields: add them as optionals on the model **and** on `HueEventResource` so
  partial event updates apply.

## Testing

```bash
make test                  # HueKit tests, then HueBarTests
HUEBAR_LIVE=1 make test    # adds read-only discovery/TLS tests against your bridge
```

- HueKit tests (`HueKit/Tests`) cover colour maths and payload decoding.
- `HueBarTests` cover the credentials file (round trip, `0600`/`0700` permissions, corrupt
  file) and store state transitions. They run through SwiftPM only, not the Xcode scheme.
- **Never let a test touch the real credentials.** Pass a temporary directory to
  `BridgeStore(credentialsDirectory:)` and `PairedBridge.load(from:)`/`save(to:)`/`clear(in:)`.
  `forgetBridge()` deletes the file it was given.
- Not yet covered: the `connect()`/`resync()` flow and anything needing `HueClient` or
  `HueDiscovery`, which have no injection seam.

### Manual UI checklist

Run before a release, with a real bridge:

1. Fresh pair via link button; cancel and retry; manual IP.
2. Toggle, dim, colour and rename a light; use Identify.
3. Room power/brightness, recall a scene, check the active highlight.
4. Bridge tab: rename, firmware check, search, remove a device (confirm dialog).
5. Forget Bridge from the gear menu, the Bridge tab and the offline view (all confirm).
6. Sleep and wake the Mac; change the bridge's address; confirm it reconnects.
7. VoiceOver pass over each tab; light and dark appearance; Reduce Motion on.

## Conventions

See `CLAUDE.md` and `.claude/swift-standards.md`: file headers (`HueBar · HueBar`,
`HueKit · HueBar`), `///` docs, `os.Logger` with subsystem `com.todddube.HueBar`, no `try!` or
force unwraps on input, British spelling in UI text. Keep the app unsandboxed.

## Releasing

1. Bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml`, `CFBundleShortVersionString`/
   `CFBundleVersion` in `HueBar/Info.plist`, and the fallback in `AppInfo.version`.
2. `make xcodeproj && make test && make app`.
3. Smoke-test `build/HueBar.app`, then tag and push.

The bundle is ad-hoc signed; distributing it to others needs a Developer ID signature and
notarisation.
