import SwiftUI
import WebKit

/// Wraps the Docs web page in a WKWebView with Bearer auth injection.
/// Uses configuration.effectiveAppURL so local dev builds load localhost:3000
/// and production builds load app.todus.app.
///
/// Pass `docId` to deep-link directly into `/mail/docs/<id>` — used by the native
/// `DocEditorView`. Default `nil` keeps the legacy index behaviour.
struct DocsBrowserView: View {
    @Environment(AppServices.self) private var services

    /// Optional document id. When set, the web view opens `/mail/docs/<id>`
    /// so the native list shell can drop the user straight into the editor.
    let docId: String?

    @State private var isLoading: Bool = true
    /// Set when the WebView's main navigation fails (offline, 5xx, expired
    /// auth). Previously the spinner just vanished, leaving a blank WebView
    /// with no error and no retry.
    @State private var loadFailed: Bool = false
    /// Bumps to force the representable to re-issue the request on Retry.
    @State private var reloadToken: Int = 0

    init(docId: String? = nil) {
        self.docId = docId
    }

    var body: some View {
        let appURL = services.configuration.effectiveAppURL
        let docsURL: URL = {
            let base = appURL.appendingPathComponent("mail/docs")
            if let docId, !docId.isEmpty {
                return base.appendingPathComponent(docId)
            }
            return base
        }()

        return ZStack {
            DocsBrowserViewRepresentable(
                bearerToken: services.authService.bearerToken,
                appURL: appURL,
                docsURL: docsURL,
                isLoading: $isLoading,
                loadFailed: $loadFailed,
                reloadToken: reloadToken
            )
            if isLoading {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.regular)
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if loadFailed {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Couldn't load documents")
                        .font(.subheadline.weight(.medium))
                    Text("Check your connection and try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        loadFailed = false
                        isLoading = true
                        reloadToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .ignoresSafeArea()
    }
}

struct DocsBrowserViewRepresentable: UIViewRepresentable {
    let bearerToken: String?
    let appURL: URL
    let docsURL: URL
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    /// Incremented by the host's Retry button — a change forces a fresh load
    /// even when the URL and token are unchanged.
    var reloadToken: Int = 0

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        let darkModeScript = """
            function applyDarkMode() {
                if (!document.documentElement || !window.matchMedia) return;
                var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                document.documentElement.classList.toggle('dark', isDark);
            }

            function listenForAppearanceChanges() {
                if (!window.matchMedia) return;
                var mq = window.matchMedia('(prefers-color-scheme: dark)');
                // Older WebKit uses addListener; newer uses addEventListener.
                if (mq.addEventListener) {
                    mq.addEventListener('change', applyDarkMode);
                } else if (mq.addListener) {
                    mq.addListener(applyDarkMode);
                }
            }

            function hideWebChromeForNativeShell() {
                // The native iOS shell renders its own title TextField above
                // the WebView and its own sidebar in the list view, so the
                // web page's title row and sidebar would visually duplicate
                // them. Selectors target the data attributes added to the
                // web page; if they're not present (older deploys, future
                // template changes), this is a harmless no-op.
                //
                // Dedupe so SPA back/forward navigations don't accumulate
                // <style> nodes in document.head over a long session.
                if (document.querySelector('style[data-todus-native-chrome]')) return;
                var s = document.createElement('style');
                s.setAttribute('data-todus-native-chrome', '1');
                s.textContent = [
                    // --- Doc-specific chrome ---
                    // Title row: native iOS shell renders its own title TextField above
                    // the WebView, so hiding the web title avoids a duplicate heading.
                    '[data-doc-page-title]{display:none!important;}',
                    // Older class-based fallbacks — keep until all deploys use data attrs.
                    '.doc-page-title{display:none!important;}',
                    '.docs-title-bar{display:none!important;}',

                    // --- ResizablePanelGroup layout repair ---
                    // The sidebar panel content is hidden via [data-doc-sidebar], but the
                    // React ResizablePanel *container* still occupies 22% of the viewport.
                    // Use CSS :has() (supported iOS 15.4+ / WebKit 604+, our min is iOS 18)
                    // to hide the whole panel and the resize drag handle, then force the
                    // editor panel to fill the remaining 100% width.
                    '[data-panel]:has([data-doc-sidebar]){display:none!important;}',
                    '[data-doc-sidebar]{display:none!important;}',
                    '[data-panel-resize-handle-id]{display:none!important;}',
                    // Override the inline flex-basis set by react-resizable-panels so the
                    // editor panel expands to fill the full group width.
                    '[data-panel]:not(:has([data-doc-sidebar])){flex:1 1 0%!important;min-width:0!important;overflow:hidden!important;}',
                ].join('');
                document.head && document.head.appendChild(s);
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                    applyDarkMode();
                    listenForAppearanceChanges();
                    hideWebChromeForNativeShell();
                }, { once: true });
            } else {
                applyDarkMode();
                listenForAppearanceChanges();
                hideWebChromeForNativeShell();
            }
        """
        let script = WKUserScript(
            source: darkModeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let currentToken = bearerToken ?? ""
        let didUrlChange = webView.url?.absoluteString != docsURL.absoluteString
        let didTokenChange = context.coordinator.lastBearerToken != currentToken
        let didRetry = context.coordinator.lastReloadToken != reloadToken
        guard didUrlChange || didTokenChange || didRetry else { return }

        var request = URLRequest(url: docsURL)
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
        context.coordinator.lastBearerToken = currentToken
        context.coordinator.lastReloadToken = reloadToken
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadFailed: $loadFailed, appURL: appURL)
    }

    /// Restricts in-WebView navigation to Todus-owned origins (or the configured app
    /// origin for local dev). External links open in the system browser via
    /// `UIApplication.open`. `javascript:` URLs are blocked outright.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var loadFailed: Bool
        var lastBearerToken: String = ""
        var lastReloadToken: Int = 0
        let appURL: URL

        init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>, appURL: URL) {
            self._isLoading = isLoading
            self._loadFailed = loadFailed
            self.appURL = appURL
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Block javascript: URLs — never useful for docs content and a known XSS vector.
            if url.scheme?.lowercased() == "javascript" {
                decisionHandler(.cancel)
                return
            }

            if isAllowedURL(url) {
                decisionHandler(.allow)
                return
            }

            if let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" {
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.isLoading = true
                self.loadFailed = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.isLoading = false
                self.loadFailed = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.isLoading = false
                self.loadFailed = Self.isRealFailure(error)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.isLoading = false
                self.loadFailed = Self.isRealFailure(error)
            }
        }

        /// NSURLErrorCancelled (-999) fires on ordinary SPA/redirect churn — not a
        /// user-visible failure, so don't surface the error overlay for it.
        private static func isRealFailure(_ error: Error) -> Bool {
            (error as NSError).code != NSURLErrorCancelled
        }

        /// True for the configured app origin and any `*.todus.app` host.
        /// Allows local dev (e.g. `localhost:3000`) by matching the configured appURL host.
        private func isAllowedURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                return false
            }
            guard let host = url.host?.lowercased() else { return false }

            // Match the configured app origin (production = app.todus.app, dev = localhost).
            if let appHost = appURL.host?.lowercased(), host == appHost { return true }

            // Allow Todus-owned production origins.
            if host == "app.todus.app" { return true }
            if host == "todus.app" { return true }
            if host.hasSuffix(".todus.app") { return true }
            return false
        }
    }
}

/// Name used by `MoreSheetView` and older call sites.
typealias DocsWebView = DocsBrowserView
