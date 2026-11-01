#!/bin/zsh
#
# Builds HueBar in release mode and assembles build/HueBar.app, ad-hoc signed.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HueBar.app"
CONTENTS="$APP/Contents"

echo "▸ Building release binary"
swift build -c release --package-path "$ROOT" >/dev/null

BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/HueBar"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/HueBar"
cp "$ROOT/HueBar/Info.plist" "$CONTENTS/Info.plist"
# Stamp the build time (UTC) so the About panel shows when this bundle was made.
plutil -replace HueBuildDate -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CONTENTS/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi
echo -n "APPL????" > "$CONTENTS/PkgInfo"

echo "▸ Signing (ad hoc)"
# Finder / file-provider sync tags folders under ~/Documents; codesign rejects them as detritus.
xattr -cr "$APP"
codesign --force --sign - --identifier com.todddube.HueBar "$APP" >/dev/null

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications"
  rm -rf /Applications/HueBar.app
  cp -R "$APP" /Applications/HueBar.app
  echo "✓ Installed /Applications/HueBar.app"
else
  echo "✓ Built $APP"
fi
