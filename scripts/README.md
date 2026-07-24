# Scripts

This folder contains utility scripts for the Zero email application. These scripts are designed to help with development, testing, and maintenance tasks that are not part of the main application flow.

## Overview

The scripts system in Zero is built using [cmd-ts](https://github.com/Schniz/cmd-ts), a TypeScript library for building type-safe command-line applications. This provides a structured way to create, organize, and run utility scripts with proper command-line argument handling, help text, and more.

## How to Run Scripts

Scripts can be run using the `scripts` command from the project root:

```bash
# Run a script from the project root
bun scripts <script-name> [options]

# Example: Run the seed-style script
bun scripts seed-style
```

This command is defined in the root `package.json` and executes the root script runner:

```json
"scripts": "dotenv -- bunx tsx ./scripts/run.ts"
```

## Available Scripts

### seed-style

Seeds the writing style matrix for a given connection with sample emails of different styles. This is useful for testing and developing the writing style features of the application.

**Usage:**

```bash
# Interactive mode (will prompt for options)
bun scripts seed-style

# With command-line options
bun scripts seed-style seed --connection-id <id> --style <style> --size <number> [--reset]
# Or reset the style matrix
bun scripts seed-style reset --connection-id <id>
```

**Options:**

- `--connection-id, -c`: The connection ID to seed the style matrix for
- `--style, -s`: The style to use (professional, persuasive, genz, concise, friendly)
- `--size, -n`: Number of emails to seed (default: 10)
- `--reset, -r`: Reset the style matrix before seeding

**Subcommands:**

- `seed`: Seeds the style matrix with sample emails
- `reset`: Resets the style matrix for a connection

## How to Add New Scripts

To add a new script to the system:

1. Create a new script file in the `apps/mail/scripts` directory or a subdirectory
2. Export a command object using the cmd-ts library
3. Register the command in `apps/mail/scripts/run.ts`

### Step 1: Create a new script file

Create a new TypeScript file for your script. For example, `apps/mail/scripts/my-script.ts`:

```typescript
import { command, option, string as stringType } from 'cmd-ts';

export const myScriptCommand = command({
  name: 'my-script',
  description: 'Description of what my script does',
  args: {
    // Define command-line arguments
    param1: option({
      type: stringType,
      long: 'param1',
      short: 'p',
      description: 'Description of param1',
    }),
  },
  handler: async (inputs) => {
    // Script implementation
    console.log(`Running my script with param1: ${inputs.param1}`);
    // Do something useful here
  },
});
```

### Step 2: Register the command

Update `apps/mail/scripts/run.ts` to include your new command:

```typescript
import { seedStyleCommand } from '@zero/mail/scripts/seed-style/seeder';
import { myScriptCommand } from '@zero/mail/scripts/my-script';
import { subcommands, run } from 'cmd-ts';

const app = subcommands({
  name: 'scripts',
  cmds: {
    'seed-style': seedStyleCommand,
    'my-script': myScriptCommand, // Add your new command here
  },
});

await run(app, process.argv.slice(2));
process.exit(0);
```

### Step 3: Run your script

You can now run your script using:

```bash
bun scripts my-script --param1 value
```

## Best Practices

When creating scripts:

1. **Use cmd-ts features**: Take advantage of the cmd-ts library for argument parsing, validation, and help text
2. **Interactive mode**: Consider supporting both interactive mode (using prompts) and command-line options
3. **Error handling**: Implement proper error handling and provide useful error messages
4. **Documentation**: Document your script's purpose, usage, and options in this README
5. **Modularity**: Break complex scripts into smaller, reusable functions
6. **Testing**: Consider adding tests for critical script functionality

## Dependencies

The scripts system uses several key dependencies:

- [cmd-ts](https://github.com/Schniz/cmd-ts): Command-line parsing and execution
- [@inquirer/prompts](https://github.com/SBoudrias/Inquirer.js): Interactive command-line prompts
- [p-all](https://github.com/sindresorhus/p-all): Run promises in parallel with limited concurrency
- [p-retry](https://github.com/sindresorhus/p-retry): Retry failed promises

---

# Parity Screenshots (`scripts/parity/`)

Cross-platform screenshot baselines live in `parity_screenshots/`. The pipeline is **manifest-driven**: every screen we care about is listed in `parity_screenshots/manifest.json`, and capture scripts iterate that manifest per platform.

Today the "check" is **presence-only**: it verifies a baseline file exists for every `{slug, platform}` tuple. There is no automated pixel diff — comparison is manual via `parity_screenshots/SCREENSHOT_LOG.md`. If we ever need true regression diffs, the file-naming convention (`<Slug>__<platform>.png`) makes it straightforward to wire in `pixelmatch` / `odiff` later.

## Commands

| Command | What it does |
| --- | --- |
| `bun parity:screenshots:check` | Verifies every `{slug, platform}` baseline file exists. Fails CI if any are missing. Supports `--surface <name>`, `--platform <name>`, `--allow-missing`. |
| `bun parity:screenshots:sync` | Regenerates `SCREENSHOT_LOG.md` from filesystem presence. |
| `bun parity:screenshots:capture:web` | Headless Playwright capture against a running web app (default `http://localhost:3000`). Uses Playwright from `packages/testing` — no root dep added. |
| `bun parity:screenshots:capture:ios` | Interactive iOS capture (you navigate the simulator manually, hit Enter to capture). |
| `bun parity:screenshots:capture:ios:auto` | Deep-link driven iOS capture (uses `xcrun simctl openurl todus://…`). |
| `bun parity:screenshots:capture:android:auto` | Deep-link driven Android capture (uses `adb`). |
| `bun parity:screenshots:capture:macos:auto` | Native macOS capture against the SwiftUI `apps/macos/TodusMac` shell (uses `xcodebuild` + `screencapture`). The script filename still says `electron` for backwards-compat of the bun script entry; the implementation no longer touches the retired Electron wrapper. |

All capture scripts accept `--surface <name>` (e.g. `--surface design-system`) to filter the manifest down to a subset.

## Design System Visual Regression

The cross-platform Design System viewers are tracked under `surface: "design-system"` in the manifest:

- **Web:** `/settings/design-system` (full-page screenshot — the page is long)
- **iOS:** Settings → Developer → Design System (single-form view, all sections captured into `DesignSystem__ios.png`; section-specific iOS slugs reuse the full-form screenshot)
- **macOS:** Settings → Developer → Design System (sheet, sidebar lets you switch between `colors`, `typography`, `radius`, `spacing`, `components`, `motion`)

All three viewers are **allowlist-gated**:

- Web checks `VITE_TODUS_ALLOWLISTED_EMAILS` (loader at `apps/web/lib/developer-access.ts`)
- iOS / macOS check `TODUS_ALLOWLISTED_EMAILS` (`packages/swift-auth/.../TodusDeveloperAccess.swift`)

You must capture while signed in as an allowlisted user, otherwise:

- Web: redirected to `/settings/general` (capture script flags this as a skip)
- iOS / macOS: the Developer section nav row is hidden

### Capture baselines

```bash
# Web — full page, signed in as allowlisted user
#   prerequisites:
#     - bun web   (or bun go to also bring up the DB)
#     - PLAYWRIGHT_SESSION_TOKEN + PLAYWRIGHT_SESSION_DATA env set
#       (see packages/testing/e2e/auth.setup.ts for how to grab these from a
#       live browser session against localhost)
PARITY_WEB_BASE_URL=http://localhost:3000 \
PLAYWRIGHT_SESSION_TOKEN=... \
PLAYWRIGHT_SESSION_DATA=... \
bun parity:screenshots:capture:web -- --surface design-system

# iOS — the deep-link auto path does NOT work for the DS surface today
# (the iOS app has no /settings/* deep-link handler; see
# apps/ios/Todus/Todus/App/TodosApp.swift .onOpenURL). Use the interactive
# capture flow: boot the simulator, sign in as an allowlisted account, then
# manually nav Settings → Developer → Design System and press Enter.
bun parity:screenshots:capture:ios -- --surface design-system

# macOS — builds + launches the native TodusMac shell, then walks
# Settings → Developer → Design System. The script is interactive for
# section-specific captures because the macOS DS sheet uses a sidebar
# selector that isn't deep-linkable yet.
bun parity:screenshots:capture:macos:auto -- --surface design-system --interactive
```

### Check baselines exist

```bash
# Just the DS surface
bun parity:screenshots:check -- --surface design-system

# Everything
bun parity:screenshots:check
```

### When the design system changes intentionally

1. Update the underlying token / component (e.g. `apps/web/app/globals.css`, `AppTheme.swift`, `MacTheme.swift`).
2. Re-capture baselines for the affected platforms with the commands above.
3. Run `bun parity:screenshots:sync` to refresh `SCREENSHOT_LOG.md`.
4. Eyeball the new vs. old PNGs in `git diff parity_screenshots/` (binary diff, but at least you'll see what files moved).
5. Commit the new baselines together with the source change so reviewers can see the visual delta.

### Known limitations / manual steps

- **No pixel-diff engine wired in.** `check-screenshots.mjs` is presence-only. If a token changes but the file path stays the same, the change is invisible to CI.
- **Auth tokens are not in CI.** `PLAYWRIGHT_SESSION_TOKEN` / `PLAYWRIGHT_SESSION_DATA` need a real signed-in session; we don't have a fake-allowlisted-user mock yet. CI can run the public surfaces (Login, Signup, NotFound) but not the gated ones.
- **macOS section-by-section requires manual navigation.** The native SwiftUI sheet uses a sidebar `selection` binding — `xcrun` has no equivalent of `simctl openurl`. The capture script logs the nav and waits for Enter (`--interactive`).
- **iOS section slugs collapse to the full DS view.** The iOS surface is a single `Form` (no tab selector), so `DesignSystemColors__ios.png` etc. all show the full form. Either accept the duplication or drop the section slugs from `iosDeepLink` in the manifest.
- **Android isn't covered.** The manifest no longer declares `android` as a platform; the Android Expo app under `apps/archived/` is not active.

### Manifest entries

```jsonc
// parity_screenshots/manifest.json (excerpt)
{
  "slug": "DesignSystem",
  "webRoute": "/settings/design-system",
  "iosDeepLink": "todus://settings/design-system",
  "macosNavigation": "Settings → Developer → Design System (opens MacDesignSystemView as a sheet)",
  "surface": "design-system",
  "gated": true,
  "notes": "Allowlist-gated …"
}
```

- `surface` — used by `--surface <name>` filter across all capture/check scripts
- `gated` — capture-web script will skip + warn rather than overwrite with the redirect target if the auth session isn't allowlisted
- `iosDeepLink` — overrides the default route mapping in `capture-ios-deeplink.mjs`
- `macosNavigation` — human-readable nav steps, printed by `capture-macos-electron.mjs` so the operator knows where to click before pressing Enter
