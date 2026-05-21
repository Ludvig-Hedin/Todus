// MARK: - Moved
//
// The action-pattern modifiers (`.inFlight(_:)`, `.hapticOnChange(_:kind:)`,
// `.confirmDestructive(item:title:...)`) and the `MacHaptic` enum now live at
// the bottom of `MacTheme.swift` so the xcodegen-generated `.xcodeproj` picks
// them up via the existing tracked file rather than needing a project regen.
//
// This file is intentionally a no-op stub — kept on disk so any reference to
// the original filename in tooling, search, or git history still resolves.

import Foundation
