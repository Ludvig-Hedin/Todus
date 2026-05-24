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
  | awk -F '[=;]' '{gsub(/ /, "", $2); print $2}')
if [ -z "$VERSION" ]; then
  echo "✗ FAIL: Could not read MARKETING_VERSION from project.pbxproj"
  exit 1
fi
DMG_NAME="Todus-${VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

echo "▶ Building Todus v$VERSION"

# ── Safety checks ────────────────────────────────────────────────────────────
echo "▶ Running pre-flight safety checks..."

if [ ! -f "$MACOS_DIR/TodusMac/Resources/TodusMac.entitlements" ]; then
  echo "✗ FAIL: TodusMac.entitlements not found"
  exit 1
fi

if find "$MACOS_DIR/TodusMac" -name ".env" | grep -q .; then
  echo "✗ FAIL: .env file found inside app sources"
  exit 1
fi

if grep -r "sk-\|AKIA\|AIza\|-----BEGIN" "$MACOS_DIR/TodusMac" --include="*.swift" -l 2>/dev/null | grep -q .; then
  echo "✗ FAIL: Possible hardcoded secret detected in Swift sources"
  exit 1
fi

echo "✓ Pre-flight checks passed"

# ── Archive ──────────────────────────────────────────────────────────────────
echo "▶ Archiving $SCHEME ($CONFIGURATION)..."
rm -rf "$ARCHIVE_PATH"

if command -v xcpretty &>/dev/null; then
  xcodebuild archive \
    -project "$MACOS_DIR/TodusMac.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=XDBG7P4V96 \
    | xcpretty
  test "${PIPESTATUS[0]}" -eq 0
else
  xcodebuild archive \
    -project "$MACOS_DIR/TodusMac.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=XDBG7P4V96
fi

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "✗ FAIL: Archive not created at $ARCHIVE_PATH"
  exit 1
fi
echo "✓ Archive created: $ARCHIVE_PATH"

# ── Export ───────────────────────────────────────────────────────────────────
echo "▶ Exporting .app..."
rm -rf "$EXPORT_PATH"

if command -v xcpretty &>/dev/null; then
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    | xcpretty
  test "${PIPESTATUS[0]}" -eq 0
else
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"
fi

APP_PATH=$(find "$EXPORT_PATH" -name "*.app" -maxdepth 2 | head -1)
if [ -z "$APP_PATH" ]; then
  echo "✗ FAIL: No .app found in $EXPORT_PATH"
  exit 1
fi
echo "✓ Exported: $APP_PATH"

# ── Verify code signature ────────────────────────────────────────────────────
echo "▶ Verifying code signature..."
if ! codesign --verify --deep --strict "$APP_PATH" 2>&1; then
  echo "✗ FAIL: Code signature verification failed"
  exit 1
fi
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
