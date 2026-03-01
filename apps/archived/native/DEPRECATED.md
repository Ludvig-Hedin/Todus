# ⚠️ DEPRECATED: apps/native

**Status**: Deprecated as of 2026-03-01

**Reason**: `apps/ios` is more complete and production-ready for TestFlight.

---

## Use apps/ios Instead

For iOS development, use **`apps/ios`** which has:

- ✅ Full native screens (not WebView-based)
- ✅ EAS build system for TestFlight
- ✅ More complete feature set (37 files vs 26 files)
- ✅ Active development and maintenance
- ✅ OAuth with iOS Keychain
- ✅ Offline support with React Query

### Quick migration:

```bash
# Instead of:
pnpm native:ios

# Use:
pnpm ios:simulator
```

---

## Exception: macOS Development

If you specifically need **React Native on macOS**, this package still provides:

```bash
pnpm native:macos
pnpm native:macos:compile
```

However, consider using `apps/macos` (Electron) for macOS desktop instead.

---

## Migration Guide

See [APPS_NATIVE_MIGRATION.md](../APPS_NATIVE_MIGRATION.md) for full migration details.

---

## Questions?

If you believe this package has unique value not present in `apps/ios`, please document it before removing this deprecation notice.
