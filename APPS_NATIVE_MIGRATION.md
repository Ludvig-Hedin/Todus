# apps/native Migration Status

**Date**: 2026-03-01
**Status**: Completed

## Outcome

The project has been consolidated to one active iPhone app and one active desktop wrapper:

- Active iPhone app: `apps/ios`
- Active desktop app: `apps/macos`

Legacy/duplicate app implementations have been archived:

- `apps/native` -> `apps/archived/native`
- `apps/webview-swift` -> `apps/archived/webview-swift`
- `apps/apple` -> `apps/archived/apple`

## Script Surface

Root `native:*` scripts were removed from `package.json` to avoid accidental double-build paths.

## Notes

Archived apps are retained for reference only. Active development should not target `apps/archived/*`.
