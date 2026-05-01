#!/usr/bin/env bash
# Submit a .app, .dmg, or .zip to Apple's notary service and staple the ticket.
#
# Usage: scripts/notarize.sh <path/to/artifact>
#
# Required env vars:
#   APPLE_ID           — your Apple ID email (e.g. you@example.com)
#   APPLE_TEAM_ID      — your 10-character Apple Developer Team ID
#   APPLE_APP_PASSWORD — app-specific password from appleid.apple.com
set -euo pipefail

ARTIFACT="${1:?Usage: $0 <path/to/artifact>}"

: "${APPLE_ID:?Set APPLE_ID to your Apple ID email}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your 10-char team ID}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD to an app-specific password}"

# Wrap a bare .app in a zip for submission (notarytool accepts .app, .dmg, .zip, .pkg)
SUBMIT="$ARTIFACT"
TMPZIP=""
if [[ "$ARTIFACT" == *.app ]]; then
    TMPZIP=$(mktemp -d)/gowi.zip
    echo "Zipping $ARTIFACT for submission..."
    ditto -c -k --keepParent "$ARTIFACT" "$TMPZIP"
    SUBMIT="$TMPZIP"
fi

echo "Submitting $SUBMIT to Apple notary service..."
xcrun notarytool submit "$SUBMIT" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

[[ -n "$TMPZIP" ]] && rm -rf "$(dirname "$TMPZIP")"

echo "Stapling ticket to $ARTIFACT..."
xcrun stapler staple "$ARTIFACT"

echo "Notarization complete: $ARTIFACT"
