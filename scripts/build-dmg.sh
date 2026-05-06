#!/usr/bin/env bash
# Build a notarized, signed DMG for distribution.
#
# Usage: scripts/build-dmg.sh
#
# Required env vars (passed through to notarize.sh):
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD — notarization credentials
#   DEVELOPER_ID — your signing identity, e.g. "Developer ID Application: Your Name (TEAMID)"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
VERSION=$(grep 'MARKETING_VERSION' "$REPO_ROOT/project.yml" | head -1 | tr -d ' "' | cut -d: -f2)
DMG_NAME="gowi-${VERSION}.dmg"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your signing identity}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your 10-char team ID}"

mkdir -p "$BUILD_DIR"

echo "Regenerating Xcode project..."
xcodegen generate --spec "$REPO_ROOT/project.yml"

echo "Building Release..."
xcodebuild -scheme gowi \
    -destination 'platform=macOS' \
    -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build

APP="$BUILD_DIR/Release/gowi.app"
if [[ ! -d "$APP" ]]; then
    echo "ERROR: built app not found at $APP" >&2
    exit 1
fi

# Re-sign Sparkle nested helpers (Xcode's signing pass doesn't always reach them).
# Sign inside-out: XPC services first, then helper apps, then the framework.
echo "Re-signing Sparkle nested helpers..."
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for xpc in "$SPARKLE_FW"/XPCServices/*.xpc; do
    codesign --force --sign "$DEVELOPER_ID" --timestamp -o runtime "$xpc"
done
for helper in "$SPARKLE_FW/Autoupdate" "$SPARKLE_FW/Updater.app"; do
    codesign --force --sign "$DEVELOPER_ID" --timestamp -o runtime "$helper"
done
# Re-sign the framework and then the app to propagate the new inner signatures.
codesign --force --sign "$DEVELOPER_ID" --timestamp -o runtime "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$DEVELOPER_ID" --timestamp \
    --entitlements "$REPO_ROOT/App/Gowi.entitlements" \
    -o runtime "$APP"

echo "Notarizing app..."
"$SCRIPT_DIR/notarize.sh" "$APP"

echo "Creating DMG..."
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/gowi.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "gowi" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

rm -rf "$STAGING"

echo "Signing DMG..."
codesign --sign "$DEVELOPER_ID" \
    --timestamp \
    "$BUILD_DIR/$DMG_NAME"

echo "DMG ready: $BUILD_DIR/$DMG_NAME"
echo ""
echo "Next: sign the DMG for Sparkle and update appcast.xml:"
echo "  .build/checkouts/Sparkle/bin/sign_update $BUILD_DIR/$DMG_NAME"
