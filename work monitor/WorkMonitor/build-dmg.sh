#!/usr/bin/env bash
# Build WorkMonitor.app, wrap it in a UDZO .dmg, optionally codesign + notarize + staple.
# Run from this directory:   ./build-dmg.sh
#
# Codesign (Developer ID Application, hardened runtime):
#   export CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
#
# Notarize (pick one) — requires CODESIGN_IDENTITY:
#   A) Keychain profile (recommended locally):
#        xcrun notarytool store-credentials "workmonitor-notary" \
#          --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password"
#        export NOTARY_KEYCHAIN_PROFILE=workmonitor-notary
#   B) Inline app-specific password:
#        export APPLE_ID=you@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
#   C) App Store Connect API key:
#        export NOTARY_KEY_PATH=AuthKey_XXX.p8 NOTARY_KEY_ID=XXX NOTARY_ISSUER=uuid-issuer

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="WorkMonitor"
ENTITLEMENTS="WorkMonitor/WorkMonitor.entitlements"
DMG_LAYOUT=$(mktemp -d "${TMPDIR:-/tmp}/workmonitor-dmg.XXXXXX")

cleanup() { rm -rf "$DMG_LAYOUT"; }
trap cleanup EXIT

echo "=== Building $APP_NAME.app ==="
./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_NAME/Info.plist")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_NAME"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "=== Codesigning (hardened runtime) ==="
  [[ -f "$ENTITLEMENTS" ]] || { echo "Missing $ENTITLEMENTS" >&2; exit 1; }
  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_NAME.app"
  codesign --verify --verbose=2 "$APP_NAME.app"
else
  echo "=== Skipping codesign (set CODESIGN_IDENTITY to enable) ===" >&2
fi

echo "=== Assembling DMG layout ==="
cp -R "$APP_NAME.app" "$DMG_LAYOUT/"
ln -sf /Applications "$DMG_LAYOUT/Applications"

echo "=== Creating $DMG_NAME ==="
hdiutil create -volname "Work Monitor ${VERSION}" \
  -srcfolder "$DMG_LAYOUT" \
  -ov -format UDZO \
  "$DMG_NAME"

NOTARY_MODE=""
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_MODE=keychain
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  NOTARY_MODE=appleid
elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
  NOTARY_MODE=apikey
fi

if [[ -n "$NOTARY_MODE" ]]; then
  [[ -n "${CODESIGN_IDENTITY:-}" ]] || {
    echo "Notarization requires a signed app bundle. Set CODESIGN_IDENTITY." >&2
    exit 1
  }
  echo "=== Notarizing ($NOTARY_MODE) ==="
  case "$NOTARY_MODE" in
    keychain)
      xcrun notarytool submit "$DMG_NAME" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
      ;;
    appleid)
      xcrun notarytool submit "$DMG_NAME" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
      ;;
    apikey)
      xcrun notarytool submit "$DMG_NAME" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER" \
        --wait
      ;;
  esac

  echo "=== Stapling notarization ticket ==="
  xcrun stapler staple "$DMG_NAME"
  xcrun stapler validate "$DMG_NAME"
  echo "Gatekeeper check (local):"
  spctl --assess --verbose --type open "$DMG_NAME" || true
else
  echo "=== Skipping notarization (set NOTARY_KEYCHAIN_PROFILE, or APPLE_* vars, or NOTARY_KEY_*) ===" >&2
fi

echo ""
echo "Done: $(pwd)/$DMG_NAME"
