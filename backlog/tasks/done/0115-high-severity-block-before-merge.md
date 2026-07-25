---
id: 0115
title: "High severity (block before merge)"
status: done
tags: [code-review, code-review-backlog]
files: [package.json, pnpm-lock.yaml, patches/novel.patch, pnpm-workspace.yaml]
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## High severity (block before merge)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### B-001 — Mixed package-manager config in `package.json` will break installs
- **Area:** repo root · **Type:** repo hygiene / build break · **Risk:** high · **Status:** open
- **Files:** `package.json`, untracked `bun.lock`
- **Summary:** New diff adds `workspaces.catalog` (bun-only syntax) and `patchedDependencies` (pnpm syntax) to the same `package.json`, while a `bun.lock` (~1.4 MB) sits alongside the canonical `pnpm-lock.yaml` (~1.0 MB). `CLAUDE.md` and every script standardize on pnpm. `pnpm install` will ignore the catalog → silently diverge from `bun install` resolutions; `pnpm.patchedDependencies` should be nested under `"pnpm": { ... }` in pnpm v9+; referenced `patches/novel.patch` may not exist.
- **Approach:** Pick one package manager. If pnpm: revert `package.json` block, move catalog entries to `pnpm-workspace.yaml`'s `catalog:`, ensure `patchedDependencies` correctly nested. Drop `bun.lock`. If bun: drop `pnpm-lock.yaml`, rewrite scripts and `CLAUDE.md`.

### B-002 — Settings `location` field may not persist end-to-end
- **Area:** apps/web, apps/server, apps/ios, apps/macos · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/web/app/(routes)/settings/general/page.tsx:152`, `apps/server/src/lib/schemas.ts:195`, plus iOS/macOS settings sheets
- **Summary:** The `location` form field is rendered, defaulted, and the Zod schema accepts it (`z.string().default('')`). What's not visible in the diff is whether the web mutation payload, the tRPC settings router write path, the iOS settings sheet, and the macOS settings sheet all actually transmit/receive the new field. If any link is missing, the user types and saves and the value silently disappears.
- **Approach:** Trace `location` from each platform's settings UI through to a DB write and confirm round-trip. Add at least one parity screenshot test or unit test pinning the wire format.

### B-003 — Refresh-token fallback ignores `expiresAt`
- **Area:** apps/server (auth) · **Type:** security · **Risk:** high · **Status:** open
- **File:** `apps/server/src/main.ts:1197-1212`
- **Summary:** New fallback selects ANY session row for `sessionUser.id` whose `token === trimmedRefreshToken`, ignoring `expiresAt`. Comment justifies this for replication lag and freshly-rotated tokens, but it also means an attacker who obtains a long-expired session token (e.g. from old logs/backups) could pair it with a current Bearer for the same user and resurrect the expired session for downstream account-linking flows.
- **Approach:** Bound the fallback to a short window (e.g. `expiresAt > now() - 15 min`). Verify whether Better Auth's `linkSocialAccount` re-validates the session token; if not, this is exploitable.

### B-004 — macOS compose body sent as raw markdown — recipients see `**bold**` literals
- **Area:** apps/macos email compose · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:411-470`, `apps/macos/TodusMac/Services/Email/EmailService.swift:818`
- **Summary:** The new formatting toolbar inserts `**`, `_`, `# `, `- `, `> ` directly into `draft.body`. `mail.send` is called with `message: draft.body` unchanged. The backend treats it as plain text or HTML, not markdown — recipients see the markdown literals.
- **Approach:** Render toolbar inserts as inline HTML (`<b>`, `<i>`, `<h1>`, `<ul><li>`) before sending, or convert markdown → HTML on send. The toolbar should also wrap the *selected text* rather than appending a placeholder at end of body.

### B-005 — macOS compose "From" account selector is non-functional
- **Area:** apps/macos email compose · **Type:** correctness · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift:805-823`, `apps/macos/TodusMac/Domain/EmailModels.swift:158`
- **Summary:** `EmailDraft.fromConnectionId` is captured by the new "From" menu but `sendEmail(_:)` never serializes it into `SendEmailInput`, and `SendEmailInput` has no `connectionId` field. Multi-account users believe they're sending from the selected account; every send actually uses the backend default.
- **Approach:** Add `connectionId: String?` to `SendEmailInput`, populate from `draft.fromConnectionId`, confirm the backend `mail.send` accepts it (web/iOS likely already do).
