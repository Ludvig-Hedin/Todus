import SwiftUI
import WebKit

// MARK: - Docs View

/// Displays the Todus Docs web page inside a WKWebView with Bearer auth injection.
/// The URL is derived from MacAppServices.loadAppURL() so that local dev builds
/// point to localhost:3000 and production builds point to app.todus.app.
struct MacDocsView: View {
    @Environment(MacAppServices.self) private var services

    var body: some View {
        MacDocsWebViewRepresentable(
            bearerToken: services.authService.bearerToken,
            appURL: MacAppServices.loadAppURL()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacDocsWebViewRepresentable: NSViewRepresentable {
    let bearerToken: String?
    let appURL: URL

    private var docsURL: URL {
        appURL.appendingPathComponent("mail/docs")
    }

    func makeNSView(context: Context) -> WKWebView {
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

        return WKWebView(frame: .zero, configuration: config)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let currentToken = bearerToken ?? ""
        let didUrlChange = context.coordinator.previousRequestedURL != docsURL.absoluteString
        let didTokenChange = context.coordinator.previousBearerToken != currentToken
        guard didUrlChange || didTokenChange else { return }

        var request = URLRequest(url: docsURL)
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
        context.coordinator.previousBearerToken = currentToken
        context.coordinator.previousRequestedURL = docsURL.absoluteString
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var previousBearerToken: String = ""
        var previousRequestedURL: String = ""
    }
}
