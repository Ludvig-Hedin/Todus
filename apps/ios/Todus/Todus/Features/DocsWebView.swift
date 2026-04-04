import SwiftUI
import WebKit

/// Wraps the Docs web page in a WKWebView with Bearer auth injection.
/// Uses configuration.effectiveAppURL so local dev builds load localhost:3000
/// and production builds load app.todus.app.
struct DocsWebView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        DocsWebViewRepresentable(
            bearerToken: services.authService.bearerToken,
            appURL: services.configuration.effectiveAppURL
        )
        .ignoresSafeArea()
    }
}

struct DocsWebViewRepresentable: UIViewRepresentable {
    let bearerToken: String?
    let appURL: URL

    private var docsURL: URL {
        appURL.appendingPathComponent("mail/docs")
    }

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
        Coordinator()
    }

    final class Coordinator {
        var lastBearerToken: String = ""
    }
}
