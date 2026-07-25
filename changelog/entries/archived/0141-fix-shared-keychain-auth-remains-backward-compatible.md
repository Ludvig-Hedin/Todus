---
id: 0141
title: "Fix — shared keychain auth remains backward compatible"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — shared keychain auth remains backward compatible

- Restored backward-compatible reads for legacy account-only Keychain items after adding the bundle service namespace.
- New writes still use the namespaced keychain entry, but upgrade installs now fall back to the previous storage shape so persisted bearer tokens and AI chat history survive the rollout.

**Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`
