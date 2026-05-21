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
                isLoading: $isLoading
            )
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        let darkModeScript = """
            function applyDarkMode() {
                if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches && document.documentElement) {
                    document.documentElement.classList.add('dark');
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', applyDarkMode, { once: true });
            } else {
                applyDarkMode();
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
        guard didUrlChange || didTokenChange else { return }

        var request = URLRequest(url: docsURL)
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
        context.coordinator.lastBearerToken = currentToken
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, appURL: appURL)
    }

    /// Restricts in-WebView navigation to Todus-owned origins (or the configured app
    /// origin for local dev). External links open in the system browser via
    /// `UIApplication.open`. `javascript:` URLs are blocked outright.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        var lastBearerToken: String = ""
        let appURL: URL

        init(isLoading: Binding<Bool>, appURL: URL) {
            self._isLoading = isLoading
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
            Task { @MainActor in self.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in self.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in self.isLoading = false }
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
