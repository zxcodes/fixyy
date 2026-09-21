#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Xcode 16.x ships a macOS 15 SDK without FoundationModels.
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

echo "▶ SWIFT=$SWIFT"
echo "▶ SDKROOT=${SDKROOT:-default}"

# Native SPM: Xcode 16.4's XCBuild only accepts macOS 15.5.
echo "▶ Building (release)…"
"$SWIFT" build -c release --product Fixyy --build-system native

if [ -f Tools/make-icon.swift ] && { [ ! -f Packaging/AppIcon.icns ] || [ Tools/make-icon.swift -nt Packaging/AppIcon.icns ]; }; then
    echo "▶ Generating app icon…"
    "$SWIFT" Tools/make-icon.swift
fi

BIN="$("$SWIFT" build -c release --product Fixyy --build-system native --show-bin-path)/Fixyy"
APP="Fixyy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Fixyy"
cp "Packaging/Info.plist" "$APP/Contents/Info.plist"
if [ -f Packaging/AppIcon.icns ]; then
    cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

IDENTITY="Fixyy Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▶ Code signing with stable identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" --identifier app.fixyy "$APP"
else
    echo "▶ Ad-hoc code signing (run ./setup-signing.sh once so Accessibility survives rebuilds)…"
    codesign --force --sign - --identifier app.fixyy "$APP"
fi

echo "✅ Built $APP"
echo "   Open it with:  open \"$APP\""
