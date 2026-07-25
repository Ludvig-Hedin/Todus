---
id: 0009
title: "Login UI Polishing & Web Alignment"
status: archived
category: Changed
release_date: 2026-02-27
source: CHANGELOG.md
---

## [2026-02-27] Login UI Polishing & Web Alignment

### Added

- **Colored Google Logo**: Added `GoogleColored` (iOS) and `GoogleColor` (Web) SVG components for better brand recognition.
- **Brand Identity**: Integrated `brand-logo.png` into both iOS and Web login screens.

### Changed

- **UI Copy**: Standardized welcome messaging to "Welcome to Todus" and "Your AI agent for emails".
- **Styling**: Implemented pill-shaped (fully rounded) buttons and inputs for a more modern and premium aesthetic.
- **Theme Support**: Verified full light/dark mode support for the iOS login screen.
- **Compatibility**: Switched iOS from `expo-image` to standard `react-native` `Image` to resolve native module resolution issues.
