import AppKit
import SwiftUI

/// Single-line email field using AppKit so `contentType` is honored. SwiftUI’s `TextField` does
/// not reliably forward `textContentType` on macOS, which blocks email autofill (Keychain, Contacts)
/// the same way as Safari and the iOS field.
struct MacEmailTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onCommit: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacEmailTextField

        init(_ parent: MacEmailTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
            if let field = obj.object as? NSTextField,
               let tv = field.currentEditor() as? NSTextView {
                tv.isAutomaticSpellingCorrectionEnabled = false
                tv.isContinuousSpellCheckingEnabled = false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.textColor = .labelColor
        field.placeholderString = "Email"
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        field.contentType = .emailAddress
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        let shouldFocus = isFocused
        DispatchQueue.main.async {
            if shouldFocus, !MacEmailTextField.isFieldOrEditorActive(field) {
                _ = field.window?.makeFirstResponder(field)
            } else if !shouldFocus, MacEmailTextField.isFieldOrEditorActive(field) {
                _ = field.window?.makeFirstResponder(nil)
            }
        }
    }

    /// When editing, first responder is the shared field editor (`NSTextView`), not the field itself.
    private static func isFieldOrEditorActive(_ field: NSTextField) -> Bool {
        guard let responder = field.window?.firstResponder else { return false }
        if responder === field { return true }
        if let ed = field.currentEditor(), ed === responder { return true }
        return false
    }
}
