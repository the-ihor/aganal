#!/usr/bin/env bash
# Build, sign, notarize, and package AGANAL for direct distribution (GitHub
# Releases): universal binary + Developer ID signature + hardened runtime +
# notarized .dmg. Then it updates docs/version.json.
#
# Prerequisites:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates).
#   2. Notarization credentials, any of:
#        - a saved notarytool keychain profile:  NOTARY_PROFILE=AGANAL-notary
#          (create once: xcrun notarytool store-credentials AGANAL-notary \
#             --apple-id you@example.com --team-id XXXXXXXXXX --password app-specific-pw)
#        - or an app-specific password in the keychain as "AGANAL-ASC"
#        - or AC_PASS in the environment
#
# Usage:  scripts/make-dmg.sh
# Env:    SIGN_ID · TEAM_ID · AC_USER · NOTARY_PROFILE · AC_PASS
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Load local secrets (TEAM_ID, AC_USER, AC_PASS, NOTARY_PROFILE) if present.
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }
OUT="$ROOT/build/dist"
APP="$OUT/AGANAL.app"
DMG="$OUT/AGANAL.dmg"
TEAM_ID="${TEAM_ID:-752556J5V6}"
AC_USER="${AC_USER:-mgorunuch.igor@gmail.com}"
REPO="${REPO:-the-ihor/aganal}"

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application.*($TEAM_ID)" | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$SIGN_ID" ] || { echo "✗ No 'Developer ID Application' certificate for team $TEAM_ID in the keychain"; exit 1; }

echo "› Building universal release…"
swift build -c release --package-path "$ROOT" --arch arm64 --arch x86_64
BINDIR="$(swift build -c release --package-path "$ROOT" --arch arm64 --arch x86_64 --show-bin-path)"

echo "› Assembling bundle…"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/AGANAL" "$APP/Contents/MacOS/AGANAL"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
[ -d "$BINDIR/AGANAL_AGANAL.bundle" ] && cp -R "$BINDIR/AGANAL_AGANAL.bundle" "$APP/Contents/Resources/"
xattr -cr "$APP"

echo "› Signing with '$SIGN_ID' (hardened runtime)…"
codesign --force --sign "$SIGN_ID" \
  --entitlements "$ROOT/Resources/AGANAL.entitlements" \
  --options runtime --timestamp "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "› Creating dmg…"
STAGE="$OUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

RW="$OUT/AGANAL-rw.dmg"
hdiutil detach "/Volumes/AGANAL" >/dev/null 2>&1 || true
hdiutil create -volname "AGANAL" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null

osascript <<'OSA' || true
tell application "Finder"
  tell disk "AGANAL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 480}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 128
    set text size of vo to 13
    set position of item "AGANAL.app" of container window to {160, 170}
    set position of item "Applications" of container window to {480, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/AGANAL" >/dev/null 2>&1 || true
hdiutil convert "$RW" -format UDZO -o "$DMG" -ov >/dev/null
rm -f "$RW"; rm -rf "$STAGE"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

echo "› Notarizing (waits for Apple)…"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
else
  AC_PASS="${AC_PASS:-$(security find-generic-password -s AGANAL-ASC -w 2>/dev/null || security find-generic-password -s VTT-ASC -w 2>/dev/null || true)}"
  [ -n "$AC_PASS" ] || { echo "✗ No notarization credential (set NOTARY_PROFILE, AGANAL-ASC keychain item, or AC_PASS)"; exit 1; }
  xcrun notarytool submit "$DMG" --apple-id "$AC_USER" --team-id "$TEAM_ID" --password "$AC_PASS" --wait
fi

echo "› Stapling…"
xcrun stapler staple "$DMG"

# Update the version feed (informational / future in-app update check).
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$ROOT/Resources/Info.plist")"
cat > "$ROOT/docs/version.json" <<EOF
{
  "version": "$VERSION",
  "build": $BUILD,
  "dmg": "https://github.com/$REPO/releases/latest/download/AGANAL.dmg",
  "notes": ""
}
EOF

echo "✓ Notarized dmg ready: $DMG"
echo "  1. Release:  gh release create v$VERSION \"$DMG\" -t \"AGANAL v$VERSION\"   (or: gh release upload v$VERSION \"$DMG\" --clobber)"
echo "  2. Publish:  commit & push docs/version.json"
echo "  Verify:      spctl -a -t open --context context:primary-signature -v \"$DMG\""
