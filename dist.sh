#!/bin/bash
# Build Fixyy.app and a drag-to-Applications disk image.
# Optional notarization (Gatekeeper-clean downloads):
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   export NOTARIZE_PROFILE="notarytool-profile"
#   ./dist.sh
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
APP="Fixyy.app"
OUT="dist"
ZIP="$OUT/Fixyy-$VERSION.zip"
DMG="$OUT/Fixyy-$VERSION.dmg"
VOL="Fixyy"

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "▶ Signing with Developer ID…"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID" --identifier app.fixyy "$APP"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▶ Zipping…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶ Building disk image…"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Fixyy.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    if [ -z "${DEVELOPER_ID:-}" ]; then
        echo "NOTARIZE_PROFILE is set but DEVELOPER_ID is not." >&2
        echo "Notarization requires a Developer ID Application signature." >&2
        exit 1
    fi
    echo "▶ Submitting disk image to notarytool…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARIZE_PROFILE" --wait
    echo "▶ Stapling…"
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "▶ Checking Gatekeeper…"
    spctl --assess --type execute --verbose "$APP"
fi

echo "✅ $DMG"
echo "   That’s the file to give people: open it, drag Fixyy onto Applications."
echo "   Publish with:  gh release create v$VERSION \"$DMG\" --title \"Fixyy $VERSION\""
