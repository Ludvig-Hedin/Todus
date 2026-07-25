---
id: 0001
title: "Confirm Apple key ZJC3UFF6WX is revoked in App Store Connect"
status: open
priority: P0
area: security
source: "CODE_REVIEW_BACKLOG.md — Release review follow-up 2026-07-24; TASK.md `MANUAL`"
created: 2026-07-25
---

The private key file is not present in the working tree, but its path still exists in old Git history, so the key may have been committed at some point. Only the account owner can check and revoke it.

- [ ] Sign in to [App Store Connect](https://appstoreconnect.apple.com/) → **Users and Access → Integrations → App Store Connect API**
- [ ] Find key ID `ZJC3UFF6WX` (team `XDBG7P4V96`)
- [ ] If it is still active, **revoke** it and generate a replacement
- [ ] Update whichever CI/secret store holds the old key with the new key id + `.p8`
- [ ] Record the outcome here (revoked / already revoked / key never existed) and close this task

Do not skip the last box: "the file is absent locally" is not evidence that the key is revoked.
