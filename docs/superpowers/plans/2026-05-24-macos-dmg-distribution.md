# macOS DMG Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a signed macOS DMG of Todus, upload it to Cloudflare R2, and wire up the /downloads page to serve it.

**Architecture:** A shell script runs `xcodebuild archive` → `xcodebuild -exportArchive` → `create-dmg` → `wrangler r2 object put`. The R2 bucket serves the file publicly. The downloads page hardcodes the R2 URL. No CI automation in this iteration.

**Tech Stack:** xcodebuild, create-dmg (homebrew), wrangler CLI (4.32.0), Cloudflare R2, React Router v7

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `apps/macos/ExportOptions.plist` | Xcode archive export config (development signing) |
| Create | `scripts/build-mac-dmg.sh` | Full build → DMG → R2 upload script |
| Modify | `apps/web/app/(full-width)/downloads.tsx` | Wire Mac download button to R2 URL |

---

## Task 1: Create R2 bucket for releases

**Files:**
- No files changed (infra step)

- [ ] **Step 1: Create the R2 bucket**

```bash
cd apps/server
npx wrangler r2 bucket create todus-releases
```

Expected output: `Created bucket 'todus-releases'`

- [ ] **Step 2: Enable public r2.dev URL on the bucket**

```bash
npx wrangler r2 bucket dev-url enable todus-releases
```

Expected: `Enabled development URL for bucket 'todus-releases'`

> If this fails, enable it in the Cloudflare dashboard:
> Cloudflare Dashboard → R2 → `todus-releases` → Settings → Public Access → R2.dev subdomain → Enable

- [ ] **Step 3: Note the public bucket URL**

The URL format will be: `https://pub-<hash>.r2.dev/mac/Todus-1.0.dmg`

Find it in Cloudflare Dashboard → R2 → todus-releases → Settings → Public Access. Save this URL — you'll need it in Task 4.

- [ ] **Step 4: Verify bucket exists**

```bash
npx wrangler r2 bucket list
```

Expected: `todus-releases` appears in the list.

---

## Task 2: Create Xcode ExportOptions.plist

**Files:**
- Create: `apps/macos/ExportOptions.plist`

This file tells `xcodebuild -exportArchive` how to sign and package the app. We use `development` method which works with automatic signing under your existing team (`XDBG7P4V96`).

> **Note on signing scope:** `development`-signed apps require the tester's Mac to be listed in your Apple Developer Portal (Devices). For testers outside your team, you'll eventually need a Developer ID certificate and `developer-id` method. For internal (your own Macs), `development` is fine.

- [ ] **Step 1: Create the file**

Create `apps/macos/ExportOptions.plist` with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>XDBG7P4V96</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```bash
git add apps/macos/ExportOptions.plist
git commit -m "build: add Xcode export options plist for DMG packaging"
```

---

## Task 3: Write the build script

**Files:**
- Create: `scripts/build-mac-dmg.sh`

- [ ] **Step 1: Create the script**

Create `scripts/build-mac-dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MACOS_DIR="$REPO_ROOT/apps/macos"
SERVER_DIR="$REPO_ROOT/apps/server"

SCHEME="TodusMac"
CONFIGURATION="Release"
ARCHIVE_PATH="$TMPDIR/Todus.xcarchive"
EXPORT_PATH="$TMPDIR/TodusExport"
EXPORT_OPTIONS="$MACOS_DIR/ExportOptions.plist"
DMG_DIR="$TMPDIR/Todus-DMG"
R2_BUCKET="todus-releases"

# ── Read version from project ────────────────────────────────────────────────
VERSION=$(grep -m1 'MARKETING_VERSION' "$MACOS_DIR/TodusMac.xcodeproj/project.pbxproj" \
  | awk -F '= ' '{print $2}' | tr -d ' ;')
DMG_NAME="Todus-${VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

echo "▶ Building Todus v$VERSION"

# ── Safety checks ────────────────────────────────────────────────────────────
echo "▶ Running pre-flight safety checks..."

# 1. Entitlements present
if [ ! -f "$MACOS_DIR/TodusMac/Resources/TodusMac.entitlements" ]; then
  echo "✗ FAIL: TodusMac.entitlements not found"
  exit 1
fi

# 2. No embedded .env files in bundle sources
if find "$MACOS_DIR/TodusMac" -name ".env" | grep -q .; then
  echo "✗ FAIL: .env file found inside app sources"
  exit 1
fi

# 3. Hardcoded secrets scan (basic — looks for common patterns)
if grep -r "sk-\|AKIA\|AIza\|-----BEGIN" "$MACOS_DIR/TodusMac" --include="*.swift" -l 2>/dev/null | grep -q .; then
  echo "✗ FAIL: Possible hardcoded secret detected in Swift sources"
  exit 1
fi

echo "✓ Pre-flight checks passed"

# ── Archive ──────────────────────────────────────────────────────────────────
echo "▶ Archiving $SCHEME ($CONFIGURATION)..."
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
  -project "$MACOS_DIR/TodusMac.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=XDBG7P4V96 \
  | xcpretty || true

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "✗ FAIL: Archive not created at $ARCHIVE_PATH"
  exit 1
fi
echo "✓ Archive created: $ARCHIVE_PATH"

# ── Export ───────────────────────────────────────────────────────────────────
echo "▶ Exporting .app..."
rm -rf "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  | xcpretty || true

APP_PATH=$(find "$EXPORT_PATH" -name "*.app" -maxdepth 2 | head -1)
if [ -z "$APP_PATH" ]; then
  echo "✗ FAIL: No .app found in $EXPORT_PATH"
  exit 1
fi
echo "✓ Exported: $APP_PATH"

# ── Verify code signature ────────────────────────────────────────────────────
echo "▶ Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH" 2>&1
echo "✓ Code signature valid"

# ── Create DMG ───────────────────────────────────────────────────────────────
echo "▶ Creating DMG..."
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"

create-dmg \
  --volname "Todus" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "Todus.app" 150 190 \
  --hide-extension "Todus.app" \
  --app-drop-link 390 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

if [ ! -f "$DMG_PATH" ]; then
  echo "✗ FAIL: DMG not created at $DMG_PATH"
  exit 1
fi

DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
echo "✓ DMG created: $DMG_PATH ($DMG_SIZE)"

# ── Upload to R2 ─────────────────────────────────────────────────────────────
echo "▶ Uploading to R2 ($R2_BUCKET)..."

(cd "$SERVER_DIR" && npx wrangler r2 object put \
  "$R2_BUCKET/mac/$DMG_NAME" \
  --file "$DMG_PATH" \
  --content-type "application/octet-stream")

echo ""
echo "✅ Done!"
echo ""
echo "   DMG:     $DMG_PATH"
echo "   Version: $VERSION"
echo ""
echo "   Update the download URL in:"
echo "   apps/web/app/(full-width)/downloads.tsx"
echo ""
echo "   R2 path: mac/$DMG_NAME"
echo "   Get the public URL from:"
echo "   Cloudflare Dashboard → R2 → $R2_BUCKET → Objects → mac/$DMG_NAME"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/build-mac-dmg.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/build-mac-dmg.sh
git commit -m "build: add macOS DMG build + R2 upload script"
```

---

## Task 4: Run the build and get the download URL

**Files:**
- None changed (this task produces the DMG artifact)

> **Prerequisite:** Xcode must be open/accessible and your Apple Developer account must be signed in to Xcode → Settings → Accounts with team `XDBG7P4V96`.

- [ ] **Step 1: Install xcpretty (makes xcodebuild output readable)**

```bash
gem install xcpretty
```

If gem install fails or is unavailable, edit `build-mac-dmg.sh` to remove the `| xcpretty || true` pipes — the script still works without it.

- [ ] **Step 2: Run the build**

From the repo root:

```bash
./scripts/build-mac-dmg.sh
```

This takes 3–10 minutes depending on machine speed. Watch for `✅ Done!` at the end.

- [ ] **Step 3: Verify the DMG is accessible**

After the upload, find the public URL:
1. Cloudflare Dashboard → R2 → `todus-releases` → Objects
2. Click `mac/Todus-1.0.dmg` → Copy Public URL

It will look like: `https://pub-<hash>.r2.dev/mac/Todus-1.0.dmg`

- [ ] **Step 4: Test the DMG locally**

```bash
open "$TMPDIR/Todus-DMG/Todus-1.0.dmg"
```

Verify: DMG mounts, Todus.app appears with an Applications folder alias. Drag to Applications, launch with right-click → Open.

---

## Task 5: Update downloads page with R2 URL

**Files:**
- Modify: `apps/web/app/(full-width)/downloads.tsx`

- [ ] **Step 1: Open the file**

File: `apps/web/app/(full-width)/downloads.tsx`

Current Mac download button (around line 55):
```tsx
<Button
  asChild
  variant="outline"
  className="w-full h-10 gap-2 border-gray-200 bg-white text-gray-900 hover:bg-gray-50 dark:border-white/10 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
>
  <a href="https://github.com/Ludvig-Hedin/Todus/releases" target="_blank" rel="noreferrer">
    <AppleIcon className="h-4 w-4" />
    Download for Mac
  </a>
</Button>
```

- [ ] **Step 2: Replace with R2 URL + internal testing note**

Replace the entire Mac `DownloadCard` block with:

```tsx
<DownloadCard
  title="Desktop App"
  description="The full Todus experience on macOS 15+."
>
  <div className="flex flex-col gap-3">
    <Button
      asChild
      variant="outline"
      className="w-full h-10 gap-2 border-gray-200 bg-white text-gray-900 hover:bg-gray-50 dark:border-white/10 dark:bg-white/5 dark:text-white dark:hover:bg-white/10"
    >
      <a href="https://pub-REPLACE_WITH_ACTUAL_HASH.r2.dev/mac/Todus-1.0.dmg" download>
        <AppleIcon className="h-4 w-4" />
        Download for Mac
      </a>
    </Button>
    <p className="text-xs text-gray-500 dark:text-white/40">
      First launch: right-click → Open to bypass the unsigned app warning.
    </p>
  </div>
</DownloadCard>
```

Replace `REPLACE_WITH_ACTUAL_HASH` with the real hash from Task 4 Step 3.

- [ ] **Step 3: Verify no TypeScript errors**

```bash
cd apps/web
npx tsc --noEmit 2>&1 | head -20
```

Expected: no errors related to downloads.tsx.

- [ ] **Step 4: Commit**

```bash
git add apps/web/app/\(full-width\)/downloads.tsx
git commit -m "feat(downloads): wire Mac DMG download to Cloudflare R2"
```

---

## Task 6: Smoke-test the live download

**Files:**
- None changed

- [ ] **Step 1: Start the web dev server**

```bash
pnpm web
```

- [ ] **Step 2: Open /downloads in browser**

Navigate to `http://localhost:5173/downloads` (or whatever port the dev server uses).

Verify:
- Mac card shows "Download for Mac" button
- Clicking it starts a file download (not a navigation)
- The file is named `Todus-1.0.dmg`
- Page renders correctly in light and dark mode

- [ ] **Step 3: Verify the R2 URL resolves**

```bash
curl -I "https://pub-REPLACE_HASH.r2.dev/mac/Todus-1.0.dmg"
```

Expected: `HTTP/2 200` with `content-type: application/octet-stream`.

---

## Task 7: Document the release process

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add changelog entry**

Add to the top of `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added
- macOS DMG build script (`scripts/build-mac-dmg.sh`) — archives, packages, and uploads to Cloudflare R2
- `/downloads` page updated to serve macOS DMG directly from R2
- Internal tester note on downloads page (right-click → Open for unsigned app)
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for macOS DMG distribution"
```

---

## Known Constraints

- **Signing scope:** `development`-signed apps require testers' Macs to be registered in Apple Developer Portal (Devices). For truly external testers, upgrade to Developer ID certificate + `developer-id` export method + optional notarization.
- **No auto-update:** Sparkle framework not configured. Testers must manually re-download for new versions.
- **R2 public URL:** The `pub-<hash>.r2.dev` URL doesn't change once the bucket is public, but looks unbranded. Add a Cloudflare custom domain to R2 later for `cdn.todus.app/mac/...`.
- **Version bump:** For each new release, bump `MARKETING_VERSION` in `project.pbxproj`, re-run the build script, and update the URL in `downloads.tsx`.
