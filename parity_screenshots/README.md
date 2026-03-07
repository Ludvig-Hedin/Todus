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

## Utility Scripts

- `pnpm parity:screenshots:sync`
  - Rebuilds [`SCREENSHOT_LOG.md`](./SCREENSHOT_LOG.md) from [`manifest.json`](./manifest.json) and current files.
- `pnpm parity:screenshots:capture:ios`
  - Interactive iOS simulator capture flow. For each screen slug, navigate in the simulator and press Enter to capture.
- `pnpm parity:screenshots:capture:ios:auto`
  - Route-driven iOS capture using deep links and simulator screenshots. Useful for quick baseline evidence.
- `pnpm parity:screenshots:capture:android:auto`
  - Route-driven Android capture using deep links (`adb shell am start ...`) and `adb exec-out screencap`.
- `pnpm parity:screenshots:capture:macos:auto`
  - Route-driven macOS capture using the existing Electron wrapper (`apps/macos`) and per-route `capturePage` exports.

## Capture Hints

- Web: Use Playwright or browser devtools at parity viewport sizes.
- iOS: `xcrun simctl io booted screenshot parity_screenshots/<ScreenName>__ios.png`
- Android: `adb exec-out screencap -p > parity_screenshots/<ScreenName>__android.png`
- macOS (Electron/web wrapper): capture from the macOS app window at matching viewport size.
  - Automated path uses `PARITY_WEB_BASE_URL` (default: `https://todus.app`) and writes `*__macos.png`.
