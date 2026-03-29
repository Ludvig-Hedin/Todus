# Todus macOS

Native SwiftUI macOS shell scaffold for Todus.

## Current Scope

This app currently provides:

- a single main window
- sidebar navigation shell
- placeholder content panes for Home, Tasks, Email, and Calendar
- a floating Assistant entry point
- placeholder Settings and account actions

No backend, shared services, or production business logic are connected yet.

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
