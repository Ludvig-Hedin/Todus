# Zero Email - Project Plan

> **Goal**: Deploy a fully functional email client accessible via **Web**, **iOS (TestFlight)**, and **macOS (TestFlight)**.

---

## Progress Overview

| Platform | Status | URL/Distribution |
|----------|--------|------------------|
| Local Dev | ✅ Complete | `http://localhost:3000` |
| Web (Production) | ✅ Live | `https://0.email` |
| iOS App | 🟡 In Progress | Expo + TestFlight |
| macOS App | 🔲 Not Started | TestFlight / Direct |

---

## Phase 1: Web Deployment (Production)

Deploy the web app to Cloudflare so it's accessible from any device.

### External Services

- [ ] Create Neon PostgreSQL database
- [ ] Create Upstash Redis database
- [ ] Enable Cloudflare R2 storage

### Cloudflare Setup

- [ ] Create Hyperdrive (database proxy)
- [ ] Create R2 bucket (`threads`)
- [ ] Create KV namespaces (10 required)
- [ ] Set production secrets

### Deployment

- [ ] Deploy backend to Cloudflare Workers
- [ ] Deploy frontend to Cloudflare Pages
- [ ] Configure custom domain (optional)
- [ ] Update Google OAuth with production redirect URI
- [ ] Verify login and email functionality

---

## Phase 2: iOS App (TestFlight)

Create a native iOS app wrapper using Expo + WebView.

### Setup

- [x] Create Expo project in `/apps/ios`
- [x] Configure `react-native-webview`
- [x] Set production URL as WebView source
- [ ] Add app icons and splash screen

### Native Features

- [ ] Push notifications (optional)
- [ ] Badge count for unread emails (optional)
- [x] Pull-to-refresh

### Distribution

- [x] Configure EAS Build (`eas.json`)
- [ ] Create App Store Connect app
- [ ] Build and upload to TestFlight
- [ ] Test on real devices

---

## Phase 3: macOS App (TestFlight)

Create a native macOS app wrapper.

### Option A: SwiftUI + WKWebView (Recommended)

- [ ] Create Xcode project in `/apps/macos`
- [ ] Implement WKWebView pointing to production URL
- [ ] Add native menu bar integration
- [ ] Add dock badge for unread count (optional)
- [ ] Configure notarization
- [ ] Submit to TestFlight

### Option B: Electron (Alternative)

- [ ] Create Electron project in `/apps/macos-electron`
- [ ] Configure BrowserWindow with production URL
- [ ] Add native menus
- [ ] Package as `.dmg`
- [ ] Notarize for distribution

---

## Current Status

**Last Updated**: 2026-02-21

### Completed

- [x] Clone repository and install dependencies
- [x] Configure environment variables
- [x] Setup local Docker (Postgres, Redis)
- [x] Initialize database schema
- [x] Fix Twilio mock for local dev
- [x] Configure Google OAuth redirect URI
- [x] Verify local login and email viewing works
- [x] Scaffold iOS Expo app in `/apps/ios`
- [x] Implement iOS WebView wrapper to production URL
- [x] Add EAS build configuration for TestFlight

### Next Steps

1. Create App Store Connect app record (user action required)
2. Run first iOS preview build with EAS
3. Upload production build to TestFlight
4. Replace placeholder app icons/splash assets

---

## Quick Commands

```bash
# Local Development
pnpm dev                    # Start dev server
pnpm db:push               # Push schema to database

# Deployment (after setup)
pnpm deploy:backend        # Deploy Workers
pnpm build:frontend        # Build frontend
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Devices                         │
├───────────────┬───────────────────────┬─────────────────────┤
│   Web Browser │    iOS (WebView)      │   macOS (WebView)   │
└───────┬───────┴───────────┬───────────┴──────────┬──────────┘
        │                   │                      │
        ▼                   ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  Cloudflare Pages (Frontend)                │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Cloudflare Workers (Backend API)             │
├───────────────┬───────────────────────┬─────────────────────┤
│  Hyperdrive   │          R2           │         KV          │
│  (Postgres)   │      (Attachments)    │      (Cache)        │
└───────────────┴───────────────────────┴─────────────────────┘
```
