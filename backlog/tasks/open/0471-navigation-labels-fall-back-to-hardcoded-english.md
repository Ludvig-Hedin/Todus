---
id: 0471
title: "Navigation labels fall back to hardcoded English"
status: open
priority: P4
tags: [web, todo-sweep, i18n]
files: [apps/web/config/navigation.ts]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`apps/web/config/navigation.ts:178` and `:199` — `TODO(i18n): Replace the English fallback once locale catalogs add this key.` Two nav entries bypass Paraglide and ship English to every locale.

## Fix shape

Add the missing keys to `apps/web/messages/` and swap the fallbacks for the compiled Paraglide accessors.
