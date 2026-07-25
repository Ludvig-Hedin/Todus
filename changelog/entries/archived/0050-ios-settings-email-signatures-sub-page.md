---
id: 0050
title: "iOS Settings — Email Signatures sub-page"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Settings — Email Signatures sub-page

### Feature: Full Signature Management

- **`SignaturesView`**: List showing all signatures with a checkmark on the active one. "None" row at top to disable signatures. Swipe-to-delete on each row. "+" toolbar button to create new. Each row navigates to the editor.
- **`SignatureEditorView`**: Name field + TextEditor for body + "Use as active signature" toggle + Delete button. Presented as a sheet for new signatures, pushed page for editing.
- **SettingsView**: Replaced the signature toggle + inline textfield with a `NavigationLink` to `SignaturesView`. Shows the active signature name (or "Off") as the row's value hint.
- **AppServices**: `signatures: [EmailSignature]` (JSON-persisted) + `selectedSignatureID: UUID?` + `activeSignature` computed property. Old `signatureEnabled`/`signatureText` properties preserved as backward-compat computed properties. Migration: existing single-text signature is imported as a "Default" signature on first launch with new version.
- **`EmailSignature` model**: `Codable + Identifiable + Sendable` struct in `Domain/EmailModels.swift`.

### Files

- `Domain/EmailModels.swift` — EmailSignature struct
- `App/AppServices.swift` — signatures/selectedSignatureID storage + migration
- `Features/Settings/SignaturesView.swift` — NEW (SignaturesView + SignatureEditorView)
- `Features/Settings/SettingsView.swift` — NavigationLink in email section
- `Todus.xcodeproj/project.pbxproj` — SignaturesView.swift registered
