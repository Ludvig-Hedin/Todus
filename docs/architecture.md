# Architecture

> Code-derived overview of how Todus fits together. Canonical landing doc: [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md). App-surface map: [`../APPS_ARCHITECTURE.md`](../APPS_ARCHITECTURE.md). Last verified: 2026-06-13.

## What Todus is

**Todus** is a unified productivity app — email, calendar, tasks, docs, meetings, and an AI assistant — built around **one shared data model and a single backend**. Email threads, calendar events, tasks, and docs share the same Postgres schema and the same tRPC API; the AI assistant operates across all of them via tool calls. Production web: `todus.app`.

It is not three apps stitched together — the web, iOS, and macOS clients are different front-ends over the same `apps/server` Cloudflare Worker.

## The monorepo (bun + Turborepo)

| App / package | Path | Stack | Role |
|---|---|---|---|
| **Web** (active) | `apps/web` | React Router v7 + Vite + Cloudflare Workers | Marketing + auth + mail product + settings + developer surface |
| Web (legacy) | `apps/mail` | React Router v7 | **READ-ONLY archive** (`@zero/mail`). Do not edit. |
| **Backend** | `apps/server` | Cloudflare Worker — Hono + tRPC + Durable Objects + Workflows | Auth, mail/AI/calendar/task APIs, email sync |
| **iOS** | `apps/ios/Todus` | Native SwiftUI (Swift 6, iOS 18+) | iPhone app |
| **macOS** | `apps/macos/TodusMac` | Native SwiftUI (Swift 6, macOS 15+) | Desktop app (DMG via R2) |
| Archived | `apps/archived` | RN / Electron / SwiftUI-WebView | Reference only |

Shared packages: `shared`, `api-client`, `design-tokens`, `ui-native` (legacy), `macos-doc-editor`, `cli` (`nizzy`), `swift-auth` (SPM), `swift-widgets` (SPM), `testing`, `tsconfig`, `eslint-config`. See [`../CLAUDE.md`](../CLAUDE.md) for per-package detail.

## Request lifecycle

```
Web (apps/web, CSR SPA)  ─┐
iOS (URLSession + Bearer) ─┼─▶  api.todus.app  ─▶  apps/server (Hono on CF Workers)
macOS (URLSession + Bearer)┘                          │
                                                       ├─ tRPC router (/api/trpc/*)  ─▶ Drizzle ─▶ Hyperdrive ─▶ Postgres
                                                       ├─ Better Auth (/api/auth/*)
                                                       ├─ MCP (/sse, /mcp, /mcp/thinking/sse)
                                                       ├─ Webhooks (/webhooks/recall, /webhooks/autumn)
                                                       └─ Google Pub/Sub push (/a8n/notify/:providerId)
```

- **Web** is a client-rendered SPA (`ssr: false`); public marketing pages are prerendered to static HTML at build for SEO. It calls the backend through the tRPC TanStack-Query client.
- **Native** clients call `POST /api/trpc/<procedure>` with a Superjson body and an `Authorization: Bearer <token>` header (token in the Keychain). See [backend.md](backend.md) and [api.md](api.md).

## Email sync flow

Inbound Gmail changes arrive via Google Pub/Sub push (`/a8n/notify/:providerId`) and a queue/Workflow pipeline:

- **Queues:** `thread_queue`, `subscribe_queue`, `send_email_queue` (env-suffixed).
- **Workflows:** `SyncThreadsWorkflow` + `SyncThreadsCoordinatorWorkflow` orchestrate async thread sync.
- **Durable Objects:** `ThreadSyncWorker`, `ZeroDriver`, `ZeroDB`, `ShardRegistry`, `WorkflowRunner` coordinate per-connection state and sharding.
- **KV** caches Gmail history IDs, in-flight thread sets, subscription/snooze/scheduled-email state.

Details + full binding list in [backend.md](backend.md).

## External integrations

| Concern | Provider |
|---|---|
| Auth | Better Auth (Google OAuth, Apple Sign In, Email OTP via Resend, phone via Twilio, email/password) |
| Mail | Gmail API (Outlook/Microsoft commented out) |
| AI | OpenRouter, Anthropic, OpenAI, Groq, Perplexity, Google Generative AI; local **MLX** on iOS/macOS |
| Billing | Autumn (over Stripe) |
| Meetings | Recall.ai (bot, transcripts, media) |
| Email delivery | Resend |
| Search/vectors | Cloudflare Vectorize |
| Analytics / monitoring | PostHog, Sentry, Axiom, Datadog (OTel) |
| Voice | ElevenLabs |

Secret names per integration: [backend.md](backend.md) §Environment. Design tokens (cross-platform): [`../DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md).
