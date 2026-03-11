# Sender Avatar Resolution

Last updated: 2026-03-11

## Source Order

Inbox and thread sender avatars now resolve in this order:

1. Google People API contact photo for the exact sender email.
2. BIMI logo for the sender domain.
3. Favicon discovered from the sender domain website, with `favicon.ico` and `apple-touch-icon.png` fallbacks.
4. Initials fallback in the client when no remote image works.

## Why This Changed

The previous implementation only queried BIMI and then an external image API URL. That worked for a small set of brands but left most senders on initials.

The new resolver improves visible coverage for:

- Real contacts already known to the connected Google account.
- Brands that publish BIMI.
- Brands that do not publish BIMI but do expose a website favicon.

## Operational Note

Google contact-photo lookup requires these OAuth scopes on Google connections:

- `https://www.googleapis.com/auth/contacts.readonly`
- `https://www.googleapis.com/auth/contacts.other.readonly`

Users who connected their Google account before this change may need to reconnect once before Google People photos can be returned. BIMI and favicon fallback continue to work without reconnecting.
