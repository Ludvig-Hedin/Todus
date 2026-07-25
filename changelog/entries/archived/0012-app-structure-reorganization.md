---
id: 0012
title: "App Structure Reorganization"
status: archived
category: Changed
release_date: 2026-03-01
source: CHANGELOG.md
---

## [2026-03-01] App Structure Reorganization

### Changed

- **apps/apple → apps/webview-swift**: Moved SwiftUI WebView wrapper to clearly indicate it's a legacy wrapper, not the primary native app (`apps/apple/` → `apps/webview-swift/`).
- **apps/native deprecation**: Marked `apps/native` as deprecated in favor of `apps/ios` which is more complete and TestFlight-ready. Added `DEPRECATED.md` to guide developers to the correct app.

### Added

- **APPS_STRUCTURE.md**: Comprehensive documentation of all apps in the monorepo with status, purpose, and recommended usage.
- **APPS_NATIVE_MIGRATION.md**: Migration plan for deprecating `apps/native` in favor of `apps/ios`.
- **SCRIPTS_GUIDE.md**: Quick reference guide for all package.json scripts with explanations and recommended workflows.

### Architecture Decision

**Primary Apps Going Forward**:

- **Web**: `apps/mail` (Next.js)
- **iOS**: `apps/ios` (Expo React Native) - TestFlight ready
- **macOS**: `apps/macos` (Electron wrapper)
- **Backend**: `apps/server` (Cloudflare Worker)

**Deprecated/Legacy**:

- `apps/native` - Less complete than apps/ios, only kept for potential macOS React Native development
- `apps/webview-swift` - Simple WebView wrapper, not a true native app
