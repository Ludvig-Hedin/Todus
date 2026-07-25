---
id: 0294
title: "Website polish + downloads page"
status: archived
category: Changed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] Website polish + downloads page

Marketing site cleanup pass on `apps/web`:

- **Hero** — Removed the "Backed by Y Combinator" badge from the hero (`components/home/HomeContent.tsx`). Pulled YC mention from the meta description in `lib/site-config.ts` and the about-page meta in `app/(full-width)/about.tsx`.
- **Navbar** (`components/navigation.tsx`) — Removed the round logo crop and the "beta" badge under it; logo now renders at its natural aspect. Removed the Resources mega-menu (Twitter / LinkedIn / Discord). Added a "Download" link pointing to the new `/downloads` page on both desktop nav and mobile sheet. Removed the social-icon row from the mobile sheet.
- **Footer** (`components/home/footer.tsx`) — Full rewrite. Killed the gradient.svg background for a flat surface. Dropped the Product column. Removed SOC2 link (we don't have SOC2). Removed the Twitter / LinkedIn / Discord row. Year is now `new Date().getFullYear()` instead of hard-coded 2025. Tightened the "Experience the Future of Email Today" headline contrast (solid white) so it reads on the flat surface.
- **Global link cleanup** — Replaced every `github.com/todus-app` / `github.com/Mail-0/Zero` URL with `github.com/Ludvig-Hedin/Todus` across `apps/web`, `.github/CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/TRANSLATION.md`, and `README.md`. The `nav-user` "Customer Support" link now points at GitHub Issues instead of Discord. Translation guide no longer mentions the (defunct) Discord server.
- **/contributors removed** — Route unregistered in `app/routes.ts` and dropped from the prerender list in `react-router.config.ts`. The old page file is left on disk but unrouted.
- **/downloads added** — New page at `app/(full-width)/downloads.tsx`, routed in `app/routes.ts` and added to the prerender list. Three cards: macOS desktop (GitHub releases), iPhone (App Store), and the web app (login button). No Android / Windows / browser-extension placeholders.
- **README rewrite** — Trimmed to a short overview + feature list + download pointer + quick-start. Self-hosting moved out to a new `SELF_HOSTING.md` at repo root. Star History section removed. Team / contributors footer removed.
