import SwiftUI
import WebKit

/// Wraps the WKWebView-based Docs page in a SwiftUI view.
/// Bearer token is injected into the initial request so the web app
/// can recognise the native session without a cookie round-trip.
struct DocsWebView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        DocsWebViewRepresentable(bearerToken: services.authService.bearerToken)
            .ignoresSafeArea()
    }
}

// MARK: - UIViewRepresentable

/// UIViewRepresentable wrapper for WKWebView that loads the web Docs page.
struct DocsWebViewRepresentable: UIViewRepresentable {
    let bearerToken: String?

    // Production URL — points to the web Docs route.
    // TODO: read from app config / environment when a config layer is added.
    private var docsURL: URL {
        URL(string: "https://app.todus.app/mail/docs")!
    }

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
}
