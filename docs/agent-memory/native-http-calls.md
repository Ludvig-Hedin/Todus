# Native API calls use URLSession, never WKWebView fetch

`WKWebView.loadHTMLString(_:baseURL:)` does **not** set the security origin — the page
always gets a `null` origin, so any cross-origin `fetch` from inline HTML fails CORS. The
`baseURL` only affects relative URL resolution.

So on iOS and macOS: WebView for navigation and rendering, `URLSession` for every API
call, with `Authorization: Bearer <token>` from the Keychain. `TodosAPIClient` does this
correctly; `getSocialAuthUrl()` in `native-auth.ts` is the reference for the auth handoff.

Session modes are `bearer` (preferred) or `web-cookie` (fallback).
