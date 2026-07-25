---
id: 0031
title: "Sender Avatar Resolution Upgrade"
status: archived
category: Changed
release_date: 2026-03-11
source: CHANGELOG.md
---

## [2026-03-11] Sender Avatar Resolution Upgrade

### Changed

- **Sender Avatars**: Replaced the previous inbox sender-avatar fallback chain of `BIMI -> external image API -> initials` with a server-backed resolver that now prefers `Google People contact photos -> BIMI -> sender domain favicon`.
- **Cross-Platform Consistency**: Updated both the web mail client and the native iOS inbox/thread sender avatars to use the same server response and favicon fallback list.

### Notes

- **Google Reconnect Requirement**: Existing Google connections may need to reconnect before contact-photo lookups work, because the new resolver requires Google Contacts read scopes in addition to the existing Gmail scopes.
