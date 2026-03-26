# iOS Native Parity Test Plan

Last updated: 2026-03-11

## Automated Test Layers

### Unit tests (logic and edge cases)

- `src/features/assistant/assistantUtils.test.ts`
- `src/features/compose/composeParity.test.ts`
- `src/features/compose/mailtoParity.test.ts`
- `src/features/mail/notesUtils.test.ts`
- `src/shared/integrations/autumn.test.ts`

Run:

```bash
pnpm --filter @zero/ios run test:unit
```

### Integration-focused tests (API contract behavior)

- `src/shared/integrations/autumn.test.ts` validates:
  - Auth header handling (`Bearer` token)
  - Endpoint targeting (`/autumn/customers`, `/autumn/attach`, `/autumn/openBillingPortal`)
  - Response parsing for checkout/billing URLs
  - Error propagation when backend denies access

## E2E / RC Manual Script

Auth flow is managed by a separate stream. For parity RC runs, use an authenticated build or a known-good auth environment.

1. Mail shell parity (`/mail/:folder`):
   - Open Inbox, Sent, Archive, Spam, Bin.
   - Verify category tabs appear for Inbox and filter results correctly.
   - Long-press thread -> selection mode, select all, archive/delete bulk actions.
   - Verify search entry points:
     - Header search trigger (`Search` label only on iOS native).
     - Drawer `Search` row.
2. Compose route parity:
   - Open compose from plus button.
   - Validate send, schedule send, templates, attachments, and undo-send banner.
   - Verify the compose chrome is a single neutral surface: icon close, compact attach/schedule actions, no inline template/attach rows, and a minimal utility bar above formatting.
3. Route alias parity:
   - Open `/create` route in app navigation context and verify redirect to compose with prefill params.
   - Open under-construction route and verify both `Go Back` and `Go to Inbox`.
4. Settings parity:
   - Confirm all settings sections open and save.
   - Verify option groups and toggles show an obvious selected state with neutral grayscale styling only.
   - Open Billing settings and verify:
     - Customer fetch (when bearer session exists).
     - Upgrade checkout opens external URL.
     - Billing portal opens external URL.
5. Integration sanity:
   - PostHog events recorded for compose/thread/billing actions.
   - Sentry captures thrown boundary/query errors in debug scenarios.
   - Autumn checkout/portal URLs resolve successfully.

## Release Gate

Ship candidate only when:

- `pnpm --filter @zero/ios run test:unit` is green
- `pnpm --filter @zero/ios run bundle:ios` is green
- Manual script above has no blockers for critical flows
