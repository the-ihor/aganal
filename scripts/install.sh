#!/usr/bin/env bash
# Build AGANAL, sign it, strip the Gatekeeper quarantine flag, and install the
# .app into /Applications so it launches like a normal app.
#
# Usage:
#   ./scripts/install.sh                 # release build → /Applications, then launch
#   ./scripts/install.sh debug           # debug build instead
#   SIGN_ID="Developer ID Application: …" ./scripts/install.sh   # real identity
#   DEST=~/Applications ./scripts/install.sh                     # install elsewhere
#   NO_LAUNCH=1 ./scripts/install.sh                             # build+install only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-${CONFIG:-release}}"
DEST="${DEST:-/Applications}"
SIGN_ID="${SIGN_ID:--}"          # "-" = ad-hoc signature (default)
APP_NAME="AGANAL.app"
SRC="$ROOT/build/$APP_NAME"
TARGET="$DEST/$APP_NAME"

# 1. Build + assemble the bundle.
echo "› Building & bundling ($CONFIG)…"
"$ROOT/scripts/make-app.sh" "$CONFIG"

# 2. Sign. Ad-hoc by default; pass SIGN_ID for a real Developer ID identity.
if [[ "$SIGN_ID" == "-" ]]; then
  echo "› Ad-hoc signing…"
else
  echo "› Signing with: $SIGN_ID"
fi
ENT="$ROOT/Resources/AGANAL.entitlements"
codesign --force --deep --options runtime \
  --entitlements "$ENT" --sign "$SIGN_ID" "$SRC"
codesign --verify --deep --strict --verbose=2 "$SRC"

# 3. Install: replace any existing copy in the destination.
echo "› Installing to ${TARGET}…"
if [[ ! -w "$DEST" ]]; then
  echo "  (need elevated permissions to write to $DEST)"
  SUDO="sudo"
else
  SUDO=""
fi
$SUDO rm -rf "$TARGET"
$SUDO cp -R "$SRC" "$TARGET"

# 4. Strip the quarantine flag so Gatekeeper doesn't block first launch.
echo "› Removing quarantine flag…"
$SUDO xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "✓ Installed $TARGET"

# 5. Launch (unless suppressed).
if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
  echo "› Launching…"
  open "$TARGET"
fi
