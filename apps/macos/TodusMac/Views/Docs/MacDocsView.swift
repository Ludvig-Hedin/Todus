import SwiftUI
import WebKit

// MARK: - Docs View

/// Displays the Todus Docs web page inside a WKWebView with Bearer auth injection.
/// Uses NSViewRepresentable (macOS) — not UIViewRepresentable (iOS).
struct MacDocsView: View {
    @Environment(MacAppServices.self) private var services

    var body: some View {
        MacDocsWebViewRepresentable(bearerToken: services.authService.bearerToken)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WKWebView Representable

struct MacDocsWebViewRepresentable: NSViewRepresentable {
    let bearerToken: String?

    private var docsURL: URL {
        URL(string: "https://app.todus.app/mail/docs")!
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject dark mode class on document start so the web page respects
        // the macOS appearance preference without requiring a manual toggle.
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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Guard prevents re-loading if the view is already showing the docs URL —
        // avoids a reload every time SwiftUI re-evaluates the view tree.
        guard webView.url?.absoluteString != docsURL.absoluteString else { return }
        var request = URLRequest(url: docsURL)
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
    }
}
