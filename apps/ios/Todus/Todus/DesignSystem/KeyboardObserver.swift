import SwiftUI
import Combine

/// Lightweight keyboard height observer for positioning views above the keyboard.
/// Usage: `@StateObject private var keyboard = KeyboardObserver()`
/// Then use `keyboard.height` to offset views or add bottom padding.
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in self?.height = height }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in self?.height = height }
            .store(in: &cancellables)
    }

    var isVisible: Bool { height > 0 }
}
