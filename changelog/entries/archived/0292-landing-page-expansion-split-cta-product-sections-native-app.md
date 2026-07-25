---
id: 0292
title: "Landing page expansion: split CTA, product sections, native-app proof, FAQ page"
status: archived
category: Changed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] Landing page expansion: split CTA, product sections, native-app proof, FAQ page

Second polish pass on `apps/web` after the cleanup of YC badge / socials / contributors:

- **CTA split out of footer** — New `components/home/cta.tsx` (`CTASection`). Flat, no card, sits inside `max-w-7xl`. Removed the gradient/rounded card that previously wrapped the "Experience the Future of Email Today" headline + columns + legal line together. Rendered from `HomeContent.tsx` as a sibling of `<Footer />`, so other pages (about, terms, pricing, downloads, contact, FAQ, blog, compare) keep using the column-only footer without the CTA.
- **Footer flat + restructured columns** — Rewrote `components/home/footer.tsx`. Drops `bg-panelDark mx-1 ... rounded-xl`; now `border-t border-white/10 bg-transparent` sitting flat against the page. Columns: **Resources** (Privacy, Terms), **Product** (Download, Pricing, FAQ, Github), **Company** (About, Contact). Year is `new Date().getFullYear()`. Bottom row keeps About / Contact / Terms / Privacy as dividers.
- **Landing page product sections** — New `components/home/product-sections.tsx`. Exports `ProductSections` (Calendar, Tasks, Meetings, Docs) and `NativeAppSection`. Each feature row is text + an inline HTML/CSS mockup (no PNGs needed — placeholder illustrations match the page's design tokens). `NativeAppSection` includes a CSS iPhone frame (notch + inbox rows) and a CSS Mac window frame (traffic lights + 3-pane mail UI) with `Download for Mac` / `Get on iPhone` CTAs underneath. Wired into `HomeContent.tsx` between the existing feature grid and the footer.
- **New `/faq` page** — `app/(full-width)/faq.tsx` using the existing Radix `Accordion` primitive. 10 entries: the original 6 from the JSON-LD block plus 4 new ones (self-host, custom domains, Outlook ETA, data handling). Route registered in `app/routes.ts`; `/faq` added to the prerender list in `react-router.config.ts`.
- **JSON-LD parity** — `structuredData.faqPage.mainEntity` in `lib/site-config.ts` now ships the same 10 Q&A pairs the FAQ page renders, so Google rich snippets stay in lock-step with the visible content.
