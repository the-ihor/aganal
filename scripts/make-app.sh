#!/usr/bin/env bash
# Build AGANAL and wrap the binary in a proper .app bundle so it launches like a
# normal macOS app (Dock icon, Finder-launchable) instead of via `swift run`.
#
# Usage:  scripts/make-app.sh [release|debug]   (default: release)
# Env:    CODESIGN_ID   override the signing identity
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AGANAL.app"

echo "› Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"
BINDIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "› Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/AGANAL" "$APP/Contents/MacOS/AGANAL"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ship the SwiftPM resource bundle (icon PNGs) so Bundle.module resolves inside
# the .app just as it does under `swift run`.
if [ -d "$BINDIR/AGANAL_AGANAL.bundle" ]; then
  cp -R "$BINDIR/AGANAL_AGANAL.bundle" "$APP/Contents/Resources/"
fi

# Sign with a stable identity so macOS keeps the same identity across rebuilds.
# Override with CODESIGN_ID; falls back to the first Apple Development cert,
# then ad-hoc.
SIGN_ID="${CODESIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 "Apple Development" | sed -E 's/.*\) ([0-9A-F]+) ".*/\1/')}"

if [ -n "${SIGN_ID:-}" ]; then
  echo "› Signing with ${SIGN_ID}…"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "› Ad-hoc signing (no Developer/Development identity found)…"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ Built $APP"
echo "  Run with: open \"$APP\""
