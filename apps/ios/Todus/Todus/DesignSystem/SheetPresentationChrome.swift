import SwiftUI
import UIKit

/// Nudges the system sheet container shadow so the card reads above the app without looking heavy.
private struct SheetPresentationShadowBoost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let vc = uiView.enclosingViewController(),
                  let sheet = vc.sheetPresentationController,
                  let presented = sheet.presentedView else { return }
            presented.layer.masksToBounds = false
            presented.layer.shadowColor = UIColor.black.cgColor
            presented.layer.shadowOpacity = 0.11
            presented.layer.shadowRadius = 18
            presented.layer.shadowOffset = CGSize(width: 0, height: -4)
        }
    }
}

private extension UIView {
    func enclosingViewController() -> UIViewController? {
        var r: UIResponder? = self
        while let cur = r {
            if let vc = cur as? UIViewController { return vc }
            r = cur.next
        }
        return nil
    }
}

extension View {
    /// Sheet fill (`AppTheme.sheetBackground`), a subtle top hairline, and a slightly stronger drop shadow.
    func appSheetBackground() -> some View {
        self
            .presentationBackground {
                ZStack(alignment: .top) {
                    AppTheme.sheetBackground.ignoresSafeArea()
                    Rectangle()
                        .fill(Color(UIColor.separator).opacity(0.36))
                        .frame(height: 1 / max(UIScreen.main.scale, 2))
                        .frame(maxWidth: .infinity)
                }
            }
            .background(SheetPresentationShadowBoost())
    }
}
