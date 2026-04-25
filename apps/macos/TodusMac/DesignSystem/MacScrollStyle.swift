import AppKit
import SwiftUI

/// AppKit chrome for scroll views: overlay thumb, no track strip, no clip view fill.
@MainActor
enum MacScrollStyle {
    private static var didInstall = false
    private static var debounceWork: DispatchWorkItem?
    private static var windowObserver: NSObjectProtocol?

    /// Call once as early as the main window appears (`TodusMacApp` root).
    static func install() {
        guard !didInstall else { return }
        didInstall = true

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MacScrollStyle.scheduleApplyToWindows()
            }
        }

        scheduleApplyToWindows()
        DispatchQueue.main.async { scheduleApplyToWindows() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            applyToAllWindows()
        }
    }

    /// Re-run the window walk (e.g. after a SwiftUI `ScrollView` is mounted, such as the assistant panel).
    static func reapplyToAllWindows() {
        scheduleApplyToWindows()
        applyToAllWindows()
    }

    /// Applies to an `NSScrollView` found by the chrome anchor. Safe to call whenever layout changes.
    static func applyChrome(to scroll: NSScrollView) {
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        // The "track" strip in SwiftUI-embedded scroll views is often the clip view background.
        let clip = scroll.contentView
        clip.drawsBackground = false
        clip.backgroundColor = .clear

        // Slightly smaller thumb (when AppKit scroller is an NSControl).
        if let v = scroll.verticalScroller {
            v.controlSize = .small
        }
        if let h = scroll.horizontalScroller {
            h.controlSize = .small
        }
    }

    private static func scheduleApplyToWindows() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { applyToAllWindows() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private static func applyToAllWindows() {
        for window in NSApp.windows {
            guard let content = window.contentView else { continue }
            applyToScrollableViews(in: content)
        }
    }

    private static func applyToScrollableViews(in view: NSView) {
        for sub in view.subviews {
            if let scroll = sub as? NSScrollView {
                applyChrome(to: scroll)
            }
            applyToScrollableViews(in: sub)
        }
    }
}

// MARK: - In-scroll anchor (reaches `NSScrollView` SwiftUI may mount late or skip in global tree walks)

/// Invisible; place in `.background` of a `ScrollView`’s content. Walks the AppKit superview chain to
/// configure the enclosing `NSScrollView` (clip view + scroller) every layout pass.
@MainActor
struct MacScrollViewChromeAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeAnchorView { ChromeAnchorView() }
    func updateNSView(_ nsView: ChromeAnchorView, context: Context) { nsView.applyChromeIfEnclosing() }
}

/// Custom `NSView` so we can re-apply in `layout` / when the view moves in the window (SwiftUI late mounts).
@MainActor
final class ChromeAnchorView: NSView {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChromeIfEnclosing()
    }

    override func layout() {
        super.layout()
        applyChromeIfEnclosing()
    }

    func applyChromeIfEnclosing() {
        var v: NSView? = self
        for _ in 0 ..< 32 {
            guard let c = v else { break }
            if let sc = c as? NSScrollView {
                MacScrollStyle.applyChrome(to: sc)
                return
            }
            v = c.superview
        }
    }
}
