# tRPC client mount keys differ from the router file names

`apps/server/src/trpc/routes/` has one file per domain, but `src/trpc/index.ts` mounts
some of them under a different key. Calling `trpc.label.*` from a client fails; the file
is `label.ts` but the key is `labels`.

| File | Client key |
|------|-----------|
| `cookies.ts` | `cookiePreferences` |
| `label.ts` | `labels` |
| `mail-assistant.ts` | `mailAssistant` |
| `tasks.ts` | exports **both** `tasks` **and** `folders` |

Everything else mounts under its own name. Full catalog: [`../api.md`](../api.md).
