---
id: 0303
title: "Web design system — Liquid Glass button + manifest-driven DS viewer"
status: archived
category: Changed
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Web design system — Liquid Glass button + manifest-driven DS viewer

Closes two yellow gaps in `DESIGN_SYSTEM_INCONSISTENCIES.md`:

- **`Button variant="glass"`** (`apps/web/components/ui/button.tsx`) — sister of iOS `LiquidGlassButtonStyle`. Backdrop-blur + saturation, hairline white border (10% in dark, 20% in light), layered shadow, press = scale 0.97 + brightness lift. Default radius uses `--radius-md` (14px) so corners match iOS `Radius.control`. Transitions use the existing `--motion-duration-fast` + `--motion-easing-standard` tokens.
- **Outline button is transparent again.** `outline` variant dropped `bg-background` → `bg-transparent` so it stops reading as a filled chip on top of card surfaces. Hover still tints with `bg-accent`. Matches iOS / macOS outline buttons.
- **DS viewer is manifest-driven.** New `_components-manifest.tsx` exports a typed `COMPONENT_MANIFEST` (name, category, file, variants/render, optional notes). The viewer maps over it grouped by category (buttons / forms / layout / feedback / overlays / navigation). Each entry shows its source file path; a dashed callout at the bottom points the next contributor at the manifest. Glass button renders over a soft gradient stage so the backdrop-blur is visible.
- **Validation** — `npx oxlint --deny-warnings` clean on the three touched files; `npx tsc --noEmit` introduced zero new errors (the pre-existing 25 errors live in unrelated files: editor, mail composer, settings forms).
