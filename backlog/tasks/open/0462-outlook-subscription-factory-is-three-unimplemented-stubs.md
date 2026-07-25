---
id: 0462
title: "Outlook subscription factory is three unimplemented stubs"
status: open
priority: P3
tags: [server, todo-sweep, outlook]
files: [apps/server/src/lib/factories/outlook-subscription.factory.ts]
created: 2026-07-25
source: code TODO/FIXME sweep
---

Subscribe, unsubscribe and Microsoft Graph token verification are all empty stubs, so Outlook push notifications cannot work. Microsoft auth is currently commented out in `apps/server/src/lib/auth.ts`, so this is dormant rather than broken — but the file reads as implemented.

```
apps/server/src/lib/factories/outlook-subscription.factory.ts:12  // TODO: Implement Outlook subscription logic
apps/server/src/lib/factories/outlook-subscription.factory.ts:19  // TODO: Implement Outlook unsubscription logic
apps/server/src/lib/factories/outlook-subscription.factory.ts:25  // TODO: Implement Microsoft Graph token verification
```

## Fix shape

Either implement against Microsoft Graph subscriptions when Microsoft auth is re-enabled, or delete the factory and its registration so no caller can believe it works.
