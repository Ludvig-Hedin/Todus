---
id: 0210
title: "Fix — macOS app icon matches iOS"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — macOS app icon matches iOS

- [UX] macOS Dock: naive scaling of a **rect** crop around the mark kept **white in the rect corners** (between glyph arms and the crop edge), so the icon still looked like a smaller sharp-edged white square on the system plate. The compose script now **floods** edge-connected “paper white” to **transparent**, keeps ink + **enclosed** counter whites, scales that blob to **~95%** of 1024, and writes `AppIcon-macos-master.png` + all `AppIcon.appiconset` sizes (`compose-macos-app-icon.py`).
- [Fix] Regenerated the macOS `AppIcon` asset (all sizes in `AppIcon.appiconset` plus `AppIcon.icns`) from the same 1024×1024 source as the iOS app (`App-Icon-1024x1024@1x.png`); the Dock had been showing the generic placeholder when those assets were outdated or mismatched.
- [Config] `Info.plist`: set `CFBundleIconName` to `AppIcon` so the bundle resolves the asset-catalog icon set reliably.
- [Build] Stopped bundling a duplicate `AppIcon.icns` as a resource; `actool` already emits the app icon from `Assets.xcassets`, and the extra copy could race and fail the build.
