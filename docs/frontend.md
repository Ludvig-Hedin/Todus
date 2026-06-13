# Frontend (`apps/web`)

> Code-derived from `apps/web/app/routes.ts`, `package.json`, `vite.config.ts`, `react-router.config.ts`, `wrangler.jsonc`. Package: `@zero/web`. Last verified: 2026-06-13.
>
> ⚠️ `apps/mail` (`@zero/mail`) is the **legacy read-only archive** — never edit it. All frontend work is in `apps/web`.

## Stack

| Concern | Tech | Version |
|---|---|---|
| Framework | React Router v7 | `^7.6.1` |
| Bundler | Vite | `^6.3.5` |
| Rendering | **`ssr: false`** (client-rendered SPA) + build-time `prerender` of public marketing pages | `react-router.config.ts` |
| Runtime | Cloudflare Workers (SPA assets via `@cloudflare/vite-plugin`) | — |
| Styling | Tailwind CSS v4 (CSS-first `@theme` in `app/globals.css`) + shadcn/ui-derived (`components.json`, lucide) | `4.1.11` |
| State | Jotai + TanStack Query | `2.12.1` / `^5.74.4` |
| Rich text | Tiptap (+ `novel`) | `2.23.0` |
| i18n | Paraglide JS (`messages/` → `paraglide/`) | `2.1.0` |
| API | tRPC client via `@trpc/tanstack-react-query` → `apps/server` | catalog |
| Auth | Better Auth client (`lib/auth-client.ts` → `signIn`/`signUp`/`signOut`/`useSession`) | catalog |
| React | React 19 (+ **React Compiler** via `babel-plugin-react-compiler`) | 19 |
| Lint | oxlint (runs in the Vite build via `vite-plugin-oxlint`) | `1.6.0` |
| Other | `motion`, `next-themes`, `sonner`, `cmdk`, `nuqs`, `@dnd-kit`, `recharts`, `posthog-js`, `@sentry/react-router`, `agents`/`partysocket`, `@elevenlabs/react` | — |

> **Not SSR.** `react-router.config.ts` sets `ssr: false`. Public marketing pages get static HTML via `prerender: [...]` for SEO; authenticated routes (`/mail`, `/settings`) are pure client-side.

## Routes (`app/routes.ts`)

**Marketing / public:** `/`, `/home`, `/about`, `/terms`, `/pricing`, `/privacy`, `/downloads`, `/contact`, `/faq`, `/hr`, `/compare/:competitor`, `/blog`, `/blog/:slug`, `/share/:slug`, `/g/:token`

**Auth:** `/login`, `/signup`

**Mail product** (`/mail` layout): `/mail` (inbox), `/mail/home`, `/mail/tasks`, `/mail/calendar`, `/mail/search`, `/mail/create`, `/mail/compose`, `/mail/meetings`, `/mail/meetings/:meetingId`, `/mail/docs`, `/mail/docs/:docId`, `/mail/under-construction/:path`, `/mail/:folder` (catch-all folder, declared last)

**Settings** (`/settings` layout): index, `appearance`, `connections`, `danger-zone`, `general`, `labels`, `categories`, `signatures`, `notifications`, `privacy`, `security`, `shortcuts`, `sharing`, `meetings`, `ai`, `local-models`, `billing`, `calendars`, **`about`**, `design-system`, `/*` (splat → `[...settings]`)

**Dev / resource:** `/developer`, `/api/mailto-handler` (registers the app as a `mailto:` handler), root `/*` → not-found.

## Environment

Vite prefix `VITE_PUBLIC_*` (plus a few `VITE_*`). `vite.config.ts` statically `define`s `VITE_PUBLIC_BACKEND_URL` / `APP_URL` / `APP_NAME` with prod fallbacks (`https://api.todus.app` / `https://todus.app` / `Todus`); per-env values in `wrangler.jsonc`.

Referenced: `VITE_PUBLIC_BACKEND_URL`, `VITE_PUBLIC_APP_URL`, `VITE_PUBLIC_APP_NAME`, `VITE_PUBLIC_SERVER_URL`, `VITE_PUBLIC_APPLE_WEB_ENABLED`, `VITE_PUBLIC_ELEVENLABS_AGENT_ID`, `VITE_PUBLIC_IMAGE_API_URL`, `VITE_PUBLIC_IMAGE_PROXY`, `VITE_PUBLIC_PHONE_NUMBER`, `VITE_PUBLIC_POSTHOG_HOST`, `VITE_PUBLIC_POSTHOG_KEY`, `VITE_PUBLIC_PARITY_AUTH_BYPASS` (dev-only), `VITE_TODUS_ALLOWLISTED_EMAILS` (developer/design-system allowlist — `lib/developer-access.ts`).

## Dev / build / deploy

```bash
pnpm dev          # apps/web + backend (react-router dev --port 3000); proxies /api,/sse,/agents → :8787
pnpm go           # docker DB + apps/web + backend (full local stack)

pnpm --filter=@zero/web build    # react-router build → build/client/
pnpm --filter=@zero/web deploy   # wrangler deploy  ← use this to ship apps/web
```

⚠️ Root `pnpm build:frontend` / `pnpm deploy:frontend` still target the **legacy** `@zero/mail`. Ship the active app with the `--filter=@zero/web` commands above. Wrangler app name is `todus` (envs `todus-local` / `-staging` / `-production`); SPA serving via `assets.not_found_handling: single-page-application`.

## Design system

Web tokens live in `apps/web/app/globals.css` (single source of truth for web). Cross-platform canonical reference: [`../DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md). The `/settings/design-system` viewer is gated to `VITE_TODUS_ALLOWLISTED_EMAILS`.
