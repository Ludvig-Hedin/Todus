---
id: 0072
title: "Comprehensive SEO Overhaul — From Zero to Indexed"
status: archived
category: Changed
release_date: 2026-03-28
source: CHANGELOG.md
---

## [2026-03-28] Comprehensive SEO Overhaul — From Zero to Indexed

### Summary

todus.app had zero Google-indexed pages. This overhaul adds all missing SEO infrastructure, creates competitor comparison pages and a blog for organic traffic, and enables pre-rendering so Google sees real HTML content.

### New Files

- `apps/mail/public/robots.txt` — Crawler directives (allow public, disallow /mail/, /settings/)
- `apps/mail/public/sitemap.xml` — All public URLs for search engine discovery
- `apps/mail/app/(full-width)/compare/[competitor]/page.tsx` — Data-driven comparison pages (vs Superhuman, Shortwave, Spark, Motion)
- `apps/mail/app/(full-width)/blog/index.tsx` — Blog index page
- `apps/mail/app/(full-width)/blog/[slug]/page.tsx` — Blog post pages with 3 initial SEO articles
- `SEO-AUDIT.md` — Full audit findings, implementation status, and content calendar

### Updated Files

- `apps/mail/lib/site-config.ts` — New title, description, Twitter cards, JSON-LD schemas (Organization, SoftwareApplication, FAQPage), 25+ target keywords
- `apps/mail/app/root.tsx` — Canonical URL, Twitter cards, keywords meta, robots meta, JSON-LD structured data, apple-touch-icon, preconnect/dns-prefetch
- `apps/mail/react-router.config.ts` — Pre-render 16 public pages for SEO (static HTML at build time)
- `apps/mail/app/routes.ts` — Added /compare/:competitor, /blog, /blog/:slug routes
- `apps/mail/app/(full-width)/about.tsx` — Page-specific SEO meta tags
- `apps/mail/app/(full-width)/pricing.tsx` — Page-specific SEO meta tags

### SEO Elements Added

- Title tag: "Todus — AI Email, Calendar & Tasks in One App"
- Meta description with value prop and YC credibility
- 25+ target keywords in meta tag
- Canonical URL on every page
- Open Graph tags (title, desc, image, dimensions, alt, site_name)
- Twitter/X Cards (summary_large_image)
- JSON-LD Organization schema
- JSON-LD SoftwareApplication schema
- JSON-LD FAQPage schema with 6 Q&As
- robots.txt with crawler directives
- sitemap.xml with all public URLs
- Pre-rendered HTML for all 16 public pages

### Verification

- Build succeeds: `pnpm --filter mail build` completes with all 16 pages pre-rendered
- Pre-rendered HTML verified to contain all meta tags, structured data, and visible content
