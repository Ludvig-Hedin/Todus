import SwiftUI
import WebKit

/// Wraps the WKWebView-based Docs page in a SwiftUI view.
/// Bearer token is injected into the initial request so the web app
/// can recognise the native session without a cookie round-trip.
struct DocsWebView: View {
    @Environment(AppServices.self) private var services

    @State private var isLoading: Bool = true

    var body: some View {
        guard let url = URL(string: "https://app.todus.app/mail/docs") else {
            // Defensive — the literal above is well-formed, but if a future change ever
            // breaks it we surface a friendly error instead of crashing on a force-unwrap.
            return AnyView(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Docs are unavailable")
                        .font(.system(size: 15, weight: .semibold))
                    Text("The Docs URL could not be constructed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        return AnyView(
            ZStack {
                DocsWebViewRepresentable(
                    docsURL: url,
                    bearerToken: services.authService.bearerToken,
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
        )
    }
}

// MARK: - UIViewRepresentable

/// UIViewRepresentable wrapper for WKWebView that loads the web Docs page.
struct DocsWebViewRepresentable: UIViewRepresentable {
    let docsURL: URL
    let bearerToken: String?
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Mirror the device colour scheme into the WebView so the web app
        // can apply its own dark-mode styles immediately on load.
        let darkModeScript = """
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.classList.add('dark');
            }
        """
        let script = WKUserScript(
            source: darkModeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // Let SwiftUI safe-area handling manage insets rather than the scroll view.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Guard: avoid reloading if the correct page is already shown.
        guard webView.url?.absoluteString != docsURL.absoluteString else { return }

        var request = URLRequest(url: docsURL)
        // Attach the Bearer token as an Authorization header on the initial
        // navigation so the web session is established without a cookie flow.
        // Note: WKWebView does NOT forward this header on subsequent navigations —
        // only the first load. That is intentional; the web app handles auth state
        // after the initial handshake.
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    /// Restricts in-WebView navigation to Todus-owned origins. External links open in the
    /// system browser via `UIApplication.open` to keep the WebView scoped to docs content.
    /// `javascript:` URLs are blocked outright as a defence-in-depth measure.
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            self._isLoading = isLoading
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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

            // Allow same-origin Todus navigations and in-page anchors.
            if isAllowedTodusURL(url) {
                decisionHandler(.allow)
                return
            }

            // Anything else (mailto:, http external link, etc.) opens in the system browser.
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

        /// True for `https://app.todus.app/*` and `https://*.todus.app/*`.
        private func isAllowedTodusURL(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https" else { return false }
            guard let host = url.host?.lowercased() else { return false }
            if host == "app.todus.app" { return true }
            if host == "todus.app" { return true }
            if host.hasSuffix(".todus.app") { return true }
            return false
        }
    }
}
