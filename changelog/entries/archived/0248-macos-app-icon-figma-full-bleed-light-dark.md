---
id: 0248
title: "— macOS app icon: Figma full-bleed, light + dark"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] — macOS app icon: Figma full-bleed, light + dark

- [UX] **macOS:** `AppIcon` is regenerated from 1024×1024 Figma (Apple template) sources with one PNG per size slot, **luminosity** `light` / `dark` for system appearance. Masters live under `TodusMac/Resources/AppIconSource/` (not in the asset catalog) for future re-exports. `actool` may still log a known “unassigned children” notice for mac app icons with appearance variants; the archive still produces a valid `AppIcon.icns`.
