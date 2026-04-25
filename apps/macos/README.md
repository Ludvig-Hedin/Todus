# Todus macOS

Native SwiftUI macOS shell scaffold for Todus.

## Current Scope

This app currently provides:

- a single main window
- sidebar navigation shell
- native services for auth, email, calendar, and AI wired through the shared Swift auth package
- first-run onboarding for Gmail, calendar access, and launch-page selection
- content panes for Home, Tasks, Email, and Calendar
- a floating Assistant entry point
- settings and account actions, including a profile menu entry that opens the settings panel

The macOS app now shares the native auth implementation with iOS through `packages/swift-auth/Sources/TodusAuth`.

## Run

```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/macos
xcodegen generate
open TodusMac.xcodeproj
```

Then run the `TodusMac` scheme from Xcode.

## Structure

```text
apps/macos/
  project.yml
  TodusMac/
    App/
      TodusMacApp.swift
      MacRootView.swift
      MacSidebarView.swift
      MacContentHeaderView.swift
      AssistantButton.swift
    Resources/
      Info.plist
```

## Notes

- `pnpm macos` still points to the retired Electron flow and is intentionally not updated in this pass.
- If Xcode command-line tools are blocked by a local license prompt, run `sudo xcodebuild -license` once before building.
- **App icon:** `TodusMac/Resources/Assets.xcassets/AppIcon.appiconset` should contain only the standard macOS `icon_*` files referenced by `Contents.json`. Regenerate them with `python3 scripts/compose-macos-app-icon.py` from `apps/macos`; the script removes stale `mac_*` appearance variants because they make `actool` treat the catalog as having unassigned children.

## Full Local Reset

Bundle ID:

- `com.ludvighedin.todus.macos`

Run this from Terminal before retesting auth:

```bash
pkill -x Todus || true

rm -rf ~/Applications/Todus.app
rm -rf /Applications/Todus.app

defaults delete com.ludvighedin.todus.macos || true
rm -rf ~/Library/Preferences/com.ludvighedin.todus.macos.plist
rm -rf ~/Library/Saved\ Application\ State/com.ludvighedin.todus.macos.savedState
rm -rf ~/Library/Caches/com.ludvighedin.todus.macos

security delete-generic-password -s com.ludvighedin.todus.macos.auth -a com.todus.auth.bearerToken login.keychain-db || true
security delete-generic-password -s com.ludvighedin.todus.macos.auth -a com.todus.auth.userEmail login.keychain-db || true
security delete-generic-password -s com.ludvighedin.todus.macos.auth -a com.todus.auth.userName login.keychain-db || true
security delete-generic-password -s com.ludvighedin.todus.macos.auth -a com.todus.auth.userImage login.keychain-db || true
```

If you are running the app from Xcode, also remove the build products:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/TodusMac-*
```
