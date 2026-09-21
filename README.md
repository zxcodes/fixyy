# Fixyy

Menu-bar writing helper for Mac. Select text, press a shortcut, and Apple’s on-device Foundation Model fixes grammar or rewrites it. Nothing leaves the machine.

- **⌘⇧G** — fix grammar in place with a diff HUD and Undo. If nothing is wrong, it says “Looks good” and does not replace.
- **⌘⇧R** — streaming rewrite card (Shorter / Clearer / Formal / Friendly / Custom) anchored to the selection, with Original | Result | Changes views and a token meter. Return applies, Esc cancels.
- Status item shows a native menu: live model status, Fix/Rewrite actions, last job, Settings, Quit.
- Settings has five tabs (General, Shortcuts, Style, Model, About); onboarding walks through Accessibility, Apple Intelligence, and a first fix.

Requires **macOS 26+**, Apple Silicon, Apple Intelligence enabled.

## Build

Xcode 16’s macOS 15 SDK does not include Foundation Models. This repo builds with the Command Line Tools macOS 26/27 SDK:

Keyboard shortcuts are Carbon global hotkeys (not the KeyboardShortcuts package) so the app builds with Command Line Tools, which lack SwiftUI `#Preview` macros.

```bash
./setup-signing.sh    # once: stable identity so Accessibility survives rebuilds
./build.sh
open Fixyy.app
```

Then grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility).

```bash
# service checks (no Accessibility, no live model)
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk
swift run --build-system native fixyy-check

# live on-device prompt fixtures (this Mac, real model)
swift run --build-system native fixyy-fixtures
```

`swift test` needs Xcode 26+; this machine’s Xcode 16 XCTest cannot load against CLT 27’s Testing.framework.

Ad-hoc signing (`codesign -s -`) will _look_ like Accessibility is on while `AXIsProcessTrusted()` stays false. Use `./setup-signing.sh`.

Not App Store: replacing text in other apps uses synthetic ⌘C/⌘V, which the sandbox forbids.

## Layout

```
Sources/Fixyy/          app logic (library)
  App/                  AppDelegate, JobCoordinator, JobSummary, AppError
  Hotkeys/              Carbon hotkeys, KeyDisplay
  Selection/            SelectionIO, PasteboardSnapshot, SelectionAnchor
  Model/                ModelClient, ModelInfo, TokenBudget, TextDiff, prompts
  Fix/                  FixService, FixHUD
  Rewrite/              RewriteService, RewriteCard
  Settings/             Prefs, SettingsWindow, ShortcutRecorder
  Onboarding/           OnboardingWindow
  UI/                   StatusItemController, StatusIcon
Sources/FixyyApp/       menu-bar entry (FixyyApp.swift)
Sources/FixyyCheck/     executable assertions (swift test can't run on CLT)
Tests/FixyyTests/       fakes + XCTest suite for machines with Xcode 26
Tools/make-icon.swift   generates Packaging/AppIcon.icns + icon candidates
Fixtures/prompts/       messy + already-correct samples
docs/superpowers/specs/ design
```
