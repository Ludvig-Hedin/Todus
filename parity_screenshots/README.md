# Parity Screenshots

This folder stores screenshot evidence for web/native visual parity.

## Naming Convention

Use one canonical screen slug and capture all platforms with this exact filename pattern:

- `ScreenName__web.png`
- `ScreenName__ios.png`
- `ScreenName__android.png`
- `ScreenName__macos.png`

Example:

- `MailInbox__web.png`
- `MailInbox__ios.png`
- `MailInbox__android.png`
- `MailInbox__macos.png`

## Required Workflow

1. Use [`manifest.json`](./manifest.json) as the source of required screenshots.
2. Capture screenshots for all four platforms per screen.
3. Add visual diff notes to [`SCREENSHOT_LOG.md`](./SCREENSHOT_LOG.md).
4. Run `pnpm parity:screenshots:check` to verify coverage.
5. Update `PARITY_CHECKLIST.md` screen entries with any accepted differences.

## Capture Hints

- Web: Use Playwright or browser devtools at parity viewport sizes.
- iOS: `xcrun simctl io booted screenshot parity_screenshots/<ScreenName>__ios.png`
- Android: `adb exec-out screencap -p > parity_screenshots/<ScreenName>__android.png`
- macOS (Electron/web wrapper): capture from the macOS app window at matching viewport size.
