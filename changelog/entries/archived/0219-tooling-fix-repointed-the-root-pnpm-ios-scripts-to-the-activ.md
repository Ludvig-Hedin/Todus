---
id: 0219
title: "Tooling Fix — Repointed the root `pnpm ios*` scripts to the active native SwiftUI app in `apps/ios/Todus` so t"
status: archived
category: Docs
release_date: 2026-04-24
source: CHANGELOG.md
---

[2026-04-24] [Tooling Fix] Repointed the root `pnpm ios*` scripts to the active native SwiftUI app in `apps/ios/Todus` so they no longer invoke the archived Expo app and fail with missing Expo module maps. Architectural tooling change. (`package.json`, `scripts/ios/open-native-project.sh`, `scripts/ios/build-native-simulator.sh`, `scripts/ios/build-native-device.sh`, `docs/development/SCRIPTS_GUIDE.md`).
