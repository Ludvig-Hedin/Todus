---
id: 0307
title: "Changed — legacy unreleased batch"
status: unreleased
category: Changed
source: CHANGELOG.md
---

### Changed

- **iOS BillingSettingsView + DesignSystemView** — minor touch-ups for token consistency.
- **iOS / macOS contrast fix** — buttons no longer render white-on-white in dark mode.
- **iOS compose** — From picker, gray placeholders, heavier scrim in CreateSheet.
- **macOS Local Models UX** — (1) "Delete weights" now goes through a `confirmDestructive` dialog instead of nuking a multi-GB download on a single misclick; (2) an "Active" badge + "In use" (disabled) menu/buttons now show which local model the chat is using, with a `MacHaptic.levelChange` on selection (Recommended/Installed rows + Ollama + HuggingFace "Use" buttons); (3) the Download button is disabled with a tooltip + inline "Not enough free space · needs ~N GB" warning when the volume can't hold the weights (≈ download size + 2 GB headroom). (`apps/macos/TodusMac/Views/Settings/MacLocalModelsView.swift`)
- **macOS Live Voice panel** — a failed session now shows a "Try again" button (reconnects via the view model's `.failed`-allowed path) instead of stranding the user on a dead panel; the mute control is disabled until the voice view model exists. (`apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`)
