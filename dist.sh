#!/bin/bash
# Build Fixyy.app and a compact drag-to-Applications disk image.
# Optional notarization (this is what removes the Gatekeeper malware dialog):
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   export NOTARIZE_PROFILE="notarytool-profile"
#   ./dist.sh
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

CLT_SWIFT="/Library/Developer/CommandLineTools/usr/bin/swift"
if [ -z "${SDKROOT:-}" ]; then
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk \
               /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
        if [ -d "$sdk/System/Library/Frameworks/FoundationModels.framework" ]; then
            export SDKROOT="$sdk"
            break
        fi
    done
fi
SWIFT="${SWIFT:-}"
if [ -z "$SWIFT" ] && [ -x "$CLT_SWIFT" ]; then
    SWIFT="$CLT_SWIFT"
fi
SWIFT="${SWIFT:-swift}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
APP="Fixyy.app"
OUT="dist"
ZIP="$OUT/Fixyy-$VERSION.zip"
DMG="$OUT/Fixyy-$VERSION.dmg"
RW="$OUT/Fixyy-rw.dmg"
VOL="Fixyy"
BG="Packaging/dmg-background.png"
WIN_W=500
WIN_H=300

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "▶ Signing with Developer ID…"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID" --identifier app.fixyy "$APP"
fi

if [ ! -f "$BG" ] || [ Tools/make-dmg-background.swift -nt "$BG" ]; then
    echo "▶ Drawing disk image background…"
    "$SWIFT" Tools/make-dmg-background.swift
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▶ Zipping…"
xattr -cr "$APP" 2>/dev/null || true
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶ Building disk image…"
STAGE="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MNT" -quiet -force 2>/dev/null || true
    rm -rf "$STAGE"
    rm -f "$RW"
}
trap cleanup EXIT

ditto "$APP" "$STAGE/Fixyy.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
cp "$BG" "$STAGE/.background/bg.png"

rm -f "$RW" "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov \
    -fs HFS+ -format UDRW "$RW" >/dev/null

MNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" \
    | awk '/\/Volumes\// { print $3; exit }')"
if [ -z "${MNT:-}" ] || [ ! -d "$MNT" ]; then
    echo "Could not mount $RW" >&2
    exit 1
fi

bless --folder "$MNT" --openfolder "$MNT" 2>/dev/null || true
chflags hidden "$MNT/.background" 2>/dev/null || true

echo "▶ Laying out Finder window…"
osascript <<EOF
tell application "Finder"
    tell disk "$VOL"
        open
        delay 0.4
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        try
            set sidebar width of container window to 0
        end try
        set bounds of container window to {360, 180, $(expr 360 + $WIN_W), $(expr 180 + $WIN_H)}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 80
        set text size of opts to 12
        set background picture of opts to file ".background:bg.png"
        set position of item "Fixyy.app" to {128, 140}
        set position of item "Applications" to {372, 140}
        close
        open
        delay 0.8
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MNT" -quiet
MNT=""
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"
trap - EXIT
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
echo "   Open it, drag Fixyy onto Applications."
echo "   Gatekeeper-clean downloads need Developer ID + notarization (see README)."
echo "   Publish with:  gh release create v$VERSION \"$DMG\" --title \"Fixyy $VERSION\""
