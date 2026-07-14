#!/usr/bin/env bash
#
# Build, sign, notarize, and package ClaudeLimit as a DMG.
#
# Usage:
#   ./scripts/release.sh [version]            # default version: 1.0.0
#
# For a Gatekeeper-clean DMG (no "app is damaged / unidentified developer"),
# set both of these before running:
#
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="claudelimit-notary"
#
# One-time setup for the notary profile (needs an Apple Developer account
# and an app-specific password from https://account.apple.com):
#
#   xcrun notarytool store-credentials "claudelimit-notary" \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Without SIGN_IDENTITY the app is ad-hoc signed: fine for your own machine,
# but anyone else must right-click the app > Open on first launch.

set -euo pipefail

APP_NAME="ClaudeLimit"
SCHEME="ClaudeLimit"
VERSION="${1:-1.0.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ClaudeLimit.xcodeproj"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_ENTITLEMENTS="$ROOT/App/ClaudeLimit.entitlements"
WIDGET_ENTITLEMENTS="$ROOT/Widget/ClaudeLimitWidget.entitlements"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }

# --- 0. Regenerate the Xcode project if xcodegen is available -------------
if command -v xcodegen >/dev/null 2>&1; then
  log "Generating Xcode project (xcodegen)"
  (cd "$ROOT" && xcodegen generate --quiet)
fi

# --- 1. Build (Release, unsigned — we sign explicitly below) --------------
log "Building $SCHEME (Release, v$VERSION)"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -1

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/${APP_NAME}WidgetExtension.appex"
[[ -d "$APP_PATH" ]] || { echo "Build product not found: $APP_PATH" >&2; exit 1; }

# --- 2. Code sign (inside-out: widget extension first, then the app) ------
if [[ -n "$SIGN_IDENTITY" ]]; then
  log "Signing with: $SIGN_IDENTITY (hardened runtime + timestamp)"
  SIGN_FLAGS=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
else
  warn "SIGN_IDENTITY not set — ad-hoc signing (Gatekeeper will warn on other Macs)"
  SIGN_FLAGS=(--force --sign -)
fi

codesign "${SIGN_FLAGS[@]}" --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX_PATH"
codesign "${SIGN_FLAGS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_PATH"

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- 3. Create DMG ---------------------------------------------------------
log "Creating $DMG_NAME"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

# --- 4. Notarize + staple (covers the app inside the DMG) ------------------
if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  log "Submitting to Apple notary service (this can take a few minutes)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"

  log "Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
elif [[ -n "$SIGN_IDENTITY" ]]; then
  warn "NOTARY_PROFILE not set — DMG is signed but NOT notarized."
  warn "macOS will still warn when others download it. See the header of this script."
else
  warn "DMG is ad-hoc signed and not notarized."
  warn "On another Mac: right-click $APP_NAME.app > Open (first launch only),"
  warn "or run: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
fi

# --- 5. Summary -------------------------------------------------------------
log "Done"
shasum -a 256 "$DMG_PATH"
du -h "$DMG_PATH" | awk '{print "size: " $1}'
