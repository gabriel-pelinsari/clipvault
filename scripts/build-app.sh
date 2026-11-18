#!/usr/bin/env bash
# Builds a release ClipVault.app into ./build with the App Sandbox and the
# hardened runtime enabled. Signs with the "ClipVault Local Signing" identity when
# it exists (see create-signing-identity.sh), otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ClipVault.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClipVault"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipVault"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-certificate -c "ClipVault Local Signing" >/dev/null 2>&1; then
  IDENTITY="ClipVault Local Signing"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "warning: signing ad hoc; macOS will re-ask for Keychain and Accessibility access after each update." >&2
  IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" --timestamp=none \
  --options runtime \
  --entitlements Resources/ClipVault.entitlements \
  --identifier io.github.gabriel-pelinsari.ClipVault \
  "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "Built $APP"
