# Verification etiquette in a shared tree

Several agents run in this repo at once, on one machine, on one branch.

- **Never run repo-wide lint or format** — `bun check`, `bun lint`, `bun format` sweep
  the whole monorepo and will reformat other people's in-flight work. Lint and format
  only the files you touched (`npx eslint <file>`, `npx prettier --write <file>`).
- **One owner per heavy gate.** Before starting a full typecheck, test suite, build, or
  Xcode build, check whether one is already running (`pgrep -alf 'tsc|vite|vitest|eslint|xcodebuild'`)
  and check memory pressure. Don't duplicate a gate another session is running.
- **Never `git add .` / `-A`.** Stage the paths you own, by name.
- Prefer focused checks: the file you changed, the package that owns it, the one test
  that covers it.
