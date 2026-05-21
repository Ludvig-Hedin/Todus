// MARK: - Moved
//
// The action-pattern modifiers (`.inFlight(_:)`, `.hapticOnChange(_:kind:)`,
// `.confirmDestructive(item:title:...)`) and `AppHaptic` enum now live at the
// bottom of `AppTheme.swift` so the iOS `.xcodeproj` (which lists files
// explicitly) picks them up without a manual project membership edit.
//
// This file is intentionally left empty — keeping it on disk avoids a stale
// reference if the project file is ever regenerated to include it.

import Foundation
