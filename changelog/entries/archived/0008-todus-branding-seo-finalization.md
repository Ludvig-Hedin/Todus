---
id: 0008
title: "Todus Branding & SEO Finalization"
status: archived
category: Changed
release_date: 2026-02-27
source: CHANGELOG.md
---

## [2026-02-27] Todus Branding & SEO Finalization

### Fixed

- **Rebranding Errors**: Fixed TypeScript lint errors resulting from incomplete rename operations in `auth.ts`, `email-sequences.tsx`, and `sanitize-tip-tap-html.ts`.

### Changed

- **Global Branding**: Renamed "Zero" to "Todus" across configuration, internationalization files (\*.json), static pages, and the footer.
- **Brand Assets**: Updated logo asset URLs, onboarding vide links, and the GitHub repository link to point to Todus domains.
- **Code Settings**: Refactored the signature field from `zeroSignature` to `todusSignature` on both the frontend and the database schema.
- **SEO Elements**: Updated title tags, meta descriptions, and application headers to index correctly for "Todus".
