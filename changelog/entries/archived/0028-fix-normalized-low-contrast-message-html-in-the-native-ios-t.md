---
id: 0028
title: "Fix — Normalized low-contrast message HTML in the native iOS thread view so dark mode no longer forces white t"
status: archived
category: Fixed
release_date: 2026-03-10
source: CHANGELOG.md
---

[2026-03-10] [Fix] Normalized low-contrast message HTML in the native iOS thread view so dark mode no longer forces white text onto pale email backgrounds. The WebView now removes only broken light backgrounds or low-contrast text combinations instead of applying a blanket dark-mode text override. User-facing change. (apps/ios/src/features/mail/MessageCard.tsx).
