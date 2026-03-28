# SEO Audit & Implementation Plan — todus.app

**Date:** 2026-03-28
**Status:** Phase 1 (Quick Wins) + Phase 2 (Comparison Pages & Blog) IMPLEMENTED

---

## Executive Summary

todus.app had **zero** Google-indexed pages. The site was a client-side rendered SPA — Google saw an empty JavaScript shell. Every competitor (Superhuman, Shortwave, Spark, Motion, Marcus AI) fully server-renders their marketing pages.

### What We Fixed (This Session)

| Fix | Status | Impact |
|-----|--------|--------|
| `robots.txt` created | ✅ Done | Tells Google what to crawl |
| `sitemap.xml` created | ✅ Done | Guides Google to all public pages |
| Canonical URLs rendered in `root.tsx` | ✅ Done | Prevents duplicate content |
| Twitter/X Cards added | ✅ Done | Rich previews on social sharing |
| Keywords meta tag added | ✅ Done | Search signal (minor but helps) |
| JSON-LD Organization schema | ✅ Done | Google Knowledge Panel eligibility |
| JSON-LD SoftwareApplication schema | ✅ Done | Rich results for software queries |
| JSON-LD FAQPage schema (6 Q&As) | ✅ Done | People Also Ask SERP feature |
| Apple touch icon link | ✅ Done | iOS bookmark appearance |
| Preconnect/dns-prefetch to API | ✅ Done | Faster page loads |
| Pre-render public pages (SSG) | ✅ Done | Google sees real HTML content |
| Page-specific meta for /about | ✅ Done | Better ranking for brand queries |
| Page-specific meta for /pricing | ✅ Done | Better ranking for pricing queries |
| 4 competitor comparison pages | ✅ Done | Captures "[X] alternative" traffic |
| Blog with 3 SEO posts | ✅ Done | Organic content marketing traffic |
| Site config keyword refresh | ✅ Done | Targets AI email/calendar/tasks keywords |
| Title tag updated | ✅ Done | "Todus — AI Email, Calendar & Tasks in One App" |
| Description updated | ✅ Done | Value prop + YC-backed credibility |

### Files Changed

| File | Change |
|------|--------|
| `apps/mail/public/robots.txt` | **NEW** — crawler directives |
| `apps/mail/public/sitemap.xml` | **NEW** — all public URLs |
| `apps/mail/lib/site-config.ts` | **UPDATED** — keywords, Twitter cards, JSON-LD schemas |
| `apps/mail/app/root.tsx` | **UPDATED** — canonical, Twitter cards, keywords, JSON-LD scripts |
| `apps/mail/react-router.config.ts` | **UPDATED** — prerender all public marketing pages |
| `apps/mail/app/routes.ts` | **UPDATED** — added /compare/:competitor, /blog, /blog/:slug routes |
| `apps/mail/app/(full-width)/about.tsx` | **UPDATED** — page-specific SEO meta tags |
| `apps/mail/app/(full-width)/pricing.tsx` | **UPDATED** — page-specific SEO meta tags |
| `apps/mail/app/(full-width)/compare/[competitor]/page.tsx` | **NEW** — data-driven comparison pages |
| `apps/mail/app/(full-width)/blog/index.tsx` | **NEW** — blog index page |
| `apps/mail/app/(full-width)/blog/[slug]/page.tsx` | **NEW** — blog post pages with 3 articles |
| `SEO-AUDIT.md` | **NEW** — this document |

---

## Keyword Strategy

### Primary Keywords (highest priority)
- `Todus` / `Todus app` / `Todus email` (branded)
- `AI email client` / `AI email assistant` / `AI email app`
- `AI calendar app` / `AI task management`
- `AI email calendar tasks`

### Secondary Keywords (comparison traffic)
- `Superhuman alternative` → `/compare/superhuman`
- `Shortwave alternative` → `/compare/shortwave`
- `Spark email alternative` → `/compare/spark`
- `Motion app alternative` → `/compare/motion`

### Long-tail Content Keywords (blog traffic)
- `best AI email apps 2026` → `/blog/best-ai-email-apps-2026`
- `AI email assistant guide` → `/blog/ai-email-assistant-guide`
- `why AI email matters` → `/blog/why-ai-email-matters`

---

## Competitor Analysis Summary

| Dimension | todus.app (BEFORE) | todus.app (AFTER) | Superhuman | Shortwave | Marcus AI |
|-----------|-------------------|-------------------|------------|-----------|-----------|
| Indexed pages | 0 | 15+ (after crawl) | 100+ | 50+ | 20+ |
| SSR/pre-rendered | No | Yes (public pages) | Full SSR | Full SSR | Full SSR |
| robots.txt | No | Yes | Yes | Yes | Yes |
| sitemap.xml | No | Yes | Yes | Yes | Yes |
| Structured data | None | 3 schemas | Yes | Some | Full |
| Blog | None | 3 posts | Active | Active | Blog |
| Comparison pages | None | 4 pages | Yes | Yes | Yes |
| Twitter Cards | None | Yes | Yes | Yes | Yes |
| Canonical URLs | Not rendered | Yes | Yes | Yes | Yes |

---

## Brand Name Challenge: "Todus" vs Cuban "toDus"

**Issue:** Googling "todus" returns results for the Cuban messaging app "toDus" which dominates that search term.

**Strategy:**
1. Target `Todus app` and `Todus AI` rather than just `Todus`
2. Build strong branded content linking to todus.app
3. JSON-LD Organization schema helps Google associate "Todus" with our domain
4. Over time, branded search will strengthen as the product grows
5. Consider SEO-specific branded terms: "Todus AI email", "Todus mail"

---

## Future Optimizations (NOT yet implemented)

### High Priority
1. **Submit sitemap to Google Search Console** — Manual step, you need to do this at [search.google.com/search-console](https://search.google.com/search-console)
2. **Verify `VITE_PUBLIC_APP_URL`** is `https://todus.app` in production wrangler config
3. **Get listed on review sites** — Submit to Efficient App, Product Hunt, ToolFinder, SourceForge
4. **OG image per page** — Create unique OG images for comparison and blog pages

### Medium Priority
5. **More blog posts** — Target 2-4 posts/month on AI email topics
6. **More comparison pages** — Canary Mail, Gmail, Marcus AI, Missive
7. **Platform-specific pages** — `/ios`, `/mac` targeting "AI email for iPhone/Mac"
8. **Use case pages** — `/for/founders`, `/for/freelancers`, `/for/teams`
9. **Video content** — Embed product demos (YouTube SEO + time-on-page)
10. **Internal linking** — Add blog/comparison links to homepage and footer

### Lower Priority
11. **Google Business Profile** (if applicable)
12. **Backlink outreach** — Guest posts on productivity blogs
13. **Hreflang tags** — When internationalization is launched
14. **Web vitals optimization** — Measure and improve LCP, CLS, INP

---

## Content Calendar (Proposed)

### April 2026
| Week | Topic | Target Keyword | Format |
|------|-------|---------------|--------|
| 1 | "How to Manage Email with AI in 2026" | how to manage email with AI | Blog post |
| 2 | "Todus vs Canary Mail" | Canary Mail alternative | Comparison page |
| 3 | "Email Overload: The Science Behind Inbox Stress" | email overload solutions | Blog post |
| 4 | "AI Email for Founders: How to Save 10 Hours/Week" | AI email for founders | Blog post |

### May 2026
| Week | Topic | Target Keyword | Format |
|------|-------|---------------|--------|
| 1 | "Gmail vs AI Email Clients: Is It Time to Switch?" | Gmail alternative AI | Blog post |
| 2 | "Todus vs Marcus AI" | Marcus AI alternative | Comparison page |
| 3 | "The Complete AI Productivity Stack for 2026" | AI productivity tools 2026 | Blog post |
| 4 | "How Open Source Email Clients Protect Your Privacy" | open source email client | Blog post |

### June 2026
| Week | Topic | Target Keyword | Format |
|------|-------|---------------|--------|
| 1 | "AI Email App for iPhone: Best Options Compared" | AI email app iPhone | Landing page + blog |
| 2 | "Todus vs Missive" | Missive alternative | Comparison page |
| 3 | "How AI Task Management Works Inside Your Inbox" | AI task management email | Blog post |
| 4 | "Why Y Combinator Backed an AI Email Startup" | (brand story) | Blog post |

---

## Manual Steps Required (You Need to Do These)

1. **Google Search Console** — Go to [search.google.com/search-console](https://search.google.com/search-console), add todus.app, verify ownership, and submit the sitemap URL: `https://todus.app/sitemap.xml`
2. **Twitter/X account** — Set up @todus_app (or similar) and uncomment `site` in `site-config.ts`
3. **Google Analytics** — Verify GA is tracking all new pages
4. **OG Image verification** — Share todus.app on Twitter/LinkedIn/Slack to verify the OG image renders correctly
5. **Review sites** — Submit Todus to Efficient App, Product Hunt, G2, ToolFinder

---

## Technical Notes

### Pre-rendering (SSG) Strategy
We chose **pre-rendering** (static site generation) over **full SSR** because:
- Full SSR would require refactoring all `clientLoader` calls to `loader` calls
- The Cloudflare Workers runtime has constraints on SSR bundle size
- Auth flows are client-side only
- Public marketing pages have static content — SSG is sufficient
- Pre-rendered HTML includes all meta tags, structured data, and visible text that Google needs

The `prerender` array in `react-router.config.ts` generates static HTML files at build time for each listed route. This means Google gets real, crawlable HTML with all SEO elements.

### Adding New Pages
When adding a new comparison or blog page:
1. Add the data to the respective component file
2. Add the route to `react-router.config.ts` prerender array
3. Add the URL to `public/sitemap.xml`
4. Re-deploy
