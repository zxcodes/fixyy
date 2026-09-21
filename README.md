# Fixyy

Select text, press a shortcut, and Apple’s on-device model fixes grammar or rewrites it. Nothing leaves this Mac.

Requires **macOS 26+**, Apple Silicon, and Apple Intelligence.

## Install

1. Download **Fixyy-\*.dmg** from [Releases](https://github.com/zxcodes/fixyy/releases).
2. Open it. Drag **Fixyy** onto the **Applications** folder in that window.
3. Eject the disk image, then open Fixyy from Applications. It lives in the **menu bar**, not the Dock.
4. macOS 26 will refuse the first launch with **Done** / **Move to Bin** — click **Done**, not Move to Bin. Then System Settings → **Privacy & Security**, scroll to the bottom, **Open Anyway**.
5. Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility).

Opening the `.app` from Downloads also works, but it won’t show the drag-to-Applications panel — that’s the disk image. Putting it in Applications is what you want for Login items and Accessibility.

That malware dialog is Gatekeeper. Double-click and right-click → Open no longer bypasses it. **Open Anyway** in Privacy & Security does. To skip the warning entirely you need an Apple Developer ID and notarization; a self-signed build cannot.

## Use

- **⌘⇧G** — fix grammar in place. The menu bar shows a spinner and “Fixing”, then “Fixed”. If nothing is wrong, it says “Looks good” and leaves the text alone. Undo in the app you were in (⌘Z).
- **⌘⇧R** — rewrite window. Pick Shorter / Clearer / Formal / Friendly, or type your own instruction. Return rewrites; ⌘Return applies; Esc closes.
- The menu bar icon shows model status, the last job, Settings, and Quit.

Shortcuts are editable in Settings. Launch at login is there too.

## Distribute

`./dist.sh` builds `Fixyy.app` and writes `dist/Fixyy-<version>.dmg` (drag-to-Applications) plus a zip. Put the disk image on a GitHub Release:

```bash
./setup-signing.sh    # once, so Accessibility survives rebuilds
./dist.sh
gh release create v1.0.0 dist/Fixyy-1.0.0.dmg --title "Fixyy 1.0.0"
```

People open the disk image, drag Fixyy onto Applications, and run it. It is **not** App Store software: replacing text in other apps uses synthetic ⌘C/⌘V, which the sandbox forbids.

### So Gatekeeper lets it open

Self-signed builds work on your Mac. Everyone else hits “Apple cannot check it for malicious software” until you notarize.

You need an [Apple Developer Program](https://developer.apple.com/programs/) membership, a **Developer ID Application** certificate in Keychain, and a notarytool keychain profile:

```bash
xcrun notarytool store-credentials notarytool-profile \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARIZE_PROFILE="notarytool-profile"
./dist.sh
```

That re-signs with the hardened runtime, notarizes the disk image, staples the ticket, and rewrites `dist/Fixyy-<version>.dmg`.

## Build from source

Xcode 16’s macOS 15 SDK does not include Foundation Models. Build with Command Line Tools and a macOS 26/27 SDK. Hotkeys are Carbon so the app still builds without SwiftUI `#Preview` macros.

```bash
./setup-signing.sh    # once
./build.sh
open Fixyy.app
```

Ad-hoc signing (`codesign -s -`) looks trusted in System Settings while `AXIsProcessTrusted()` stays false. Use `./setup-signing.sh`.

```bash
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk
swift run --build-system native fixyy-check      # no Accessibility, no live model
swift run --build-system native fixyy-fixtures   # this Mac, real model
```

`swift test` needs Xcode 26+. Xcode 16’s XCTest cannot load against CLT 27’s Testing.framework.
