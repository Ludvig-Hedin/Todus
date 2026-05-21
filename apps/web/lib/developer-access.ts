/**
 * Gates Developer Mode UI (settings toggle, debug sections, design system
 * viewer) to specific accounts. Mirrors the Swift-side
 * `TodusDeveloperAccess` in `packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift`
 * so the three platforms (web, iOS, macOS) share the same allowlist semantics.
 *
 * Source of truth: `VITE_TODUS_ALLOWLISTED_EMAILS` (comma-separated, trimmed,
 * lowercased at parse time). Vite inlines this at build time, so changes
 * require a restart of the dev server / a rebuild.
 */

const ALLOWLIST_RAW = import.meta.env.VITE_TODUS_ALLOWLISTED_EMAILS ?? '';

function parseAllowlist(raw: string): Set<string> {
  if (!raw) return new Set();
  return new Set(
    raw
      .split(',')
      .map((part) => part.trim().toLowerCase())
      .filter(Boolean),
  );
}

const allowlist = parseAllowlist(ALLOWLIST_RAW);

export function isAllowlisted(email: string | null | undefined): boolean {
  if (!email) return false;
  return allowlist.has(email.trim().toLowerCase());
}

export function getAllowlistedEmails(): Set<string> {
  return new Set(allowlist);
}
