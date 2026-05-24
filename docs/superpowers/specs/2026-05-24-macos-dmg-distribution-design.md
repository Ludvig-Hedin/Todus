# macOS DMG Distribution — Design Spec

**Date:** 2026-05-24  
**Status:** Approved

## Goal

Build a signed macOS DMG of the Todus desktop app, host it on Cloudflare R2, and surface it on the `/downloads` page. Scoped to internal testing — no notarization, public access.

## Scope

- Manual build script (no CI for now)
- No notarization (internal testers bypass Gatekeeper via right-click > Open)
- Public download link (no allowlist gating)
- Cloudflare R2 for hosting

## Components

### 1. Build Script — `scripts/build-mac-dmg.sh`

Steps:
1. Run `xcodebuild archive` against the `TodusMac` scheme, Release config
2. Export `.app` via `xcodebuild -exportArchive` with a Development export options plist
3. Create DMG using `create-dmg` (or `hdiutil` fallback) — window size 540×380, app + Applications folder alias
4. Upload to R2 bucket `todus-releases` at `mac/Todus-{version}.dmg` via `wrangler r2 object put`
5. Print the public URL

### 2. Cloudflare R2 Bucket — `todus-releases`

- Public bucket with a custom domain or R2.dev public URL
- Path convention: `mac/Todus-{MARKETING_VERSION}.dmg`
- A `mac/latest.dmg` alias (or just update the URL in the downloads page per release)

### 3. Downloads Page Update — `apps/web/app/(full-width)/downloads.tsx`

- Mac card button: replace GitHub releases link with direct R2 DMG URL
- Add a small note: "macOS 14+ required · First launch: right-click → Open"

### 4. Safety Pre-flight (checked by build script)

- Valid code signature (`codesign --verify`)
- Entitlements present (`TodusMac.entitlements`)
- No embedded `.env` or secrets in the app bundle
- Info.plist has all required NSUsageDescription keys

## Out of Scope

- Notarization (future)
- GitHub Actions automation (future)
- Sparkle auto-update (future)
- Access gating / allowlist (future)

## Internal Tester Instructions

1. Download the DMG from todus.app/downloads
2. Open the DMG, drag Todus to Applications
3. First launch: right-click Todus.app → Open → Open (bypasses unsigned app warning)
