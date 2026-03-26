# Architecture Documentation

This folder contains comprehensive system design and technical architecture documentation for Todus.

## 📚 Documents

### APPS_ARCHITECTURE.md
High-level overview of all Todus applications and runtime targets:
- **iPhone** - Expo + React Native (apps/ios)
- **Desktop** - Electron WebView wrapper (apps/macos)
- **Web** - Next.js application (apps/mail)
- **Backend** - Cloudflare Worker API (apps/server)

Includes information about archived implementations and build entry points.

### APPS_STRUCTURE.md
Detailed structure and organization of active applications with:
- Build commands for each app
- Purpose and technology stack
- Command policies for development
- Guidance on using only canonical app paths

## 🎯 Quick Reference

| App | Type | Command | Purpose |
|-----|------|---------|---------|
| iOS | React Native | `pnpm ios*` | Primary mobile app |
| macOS | Electron | `pnpm macos` | Desktop wrapper |
| Web | Next.js | `pnpm dev` | Main web app |
| Backend | Cloudflare Worker | `pnpm deploy:backend` | API & auth |

## 🚫 Important

Do not use archived app implementations (`apps/archived/*`) for active development. They are reference-only.

## 📖 For More Information

- See [`../deployment/`](../deployment/) for deployment architecture
- See [`../development/`](../development/) for development setup
- See [`../README.md`](../README.md) for complete documentation index
