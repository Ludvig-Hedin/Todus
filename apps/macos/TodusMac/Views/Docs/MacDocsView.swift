import SwiftUI
import WebKit

// MARK: - Docs View

/// Displays the Todus Docs web page inside a WKWebView with Bearer auth injection.
/// Uses NSViewRepresentable (macOS) — not UIViewRepresentable (iOS).
struct MacDocsView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Without a bearer token the docs site can't authenticate the request and would
        // show a backend-rendered sign-in page. Surface a clean placeholder instead so
        // the user understands they need to sign in first.
        if let token = services.authService.bearerToken, !token.isEmpty {
            MacDocsWebViewRepresentable(
                bearerToken: token,
                isDarkMode: colorScheme == .dark
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Sign in to access docs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Your documents live in your authenticated workspace. Sign in to load them here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - WKWebView Representable

struct MacDocsWebViewRepresentable: NSViewRepresentable {
    let bearerToken: String
    let isDarkMode: Bool

    private var docsURL: URL {
        URL(string: "https://app.todus.app/mail/docs")!
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject dark mode class on document start so the web page respects
        // the macOS appearance preference without requiring a manual toggle.
        // The `data-todus-dark-init` flag is read in updateNSView so we don't
        // double-apply on subsequent reloads.
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
        // Re-apply the dark mode class on every update so toggling the macOS
        // appearance while the docs view is open is reflected immediately. The
        // initial @WKUserScript only runs at document start, so without this
        // path the page would stay in its first-loaded scheme until reload.
        let toggleJS = "document.documentElement && document.documentElement.classList.toggle('dark', \(isDarkMode));"
        webView.evaluateJavaScript(toggleJS, completionHandler: nil)

        // Guard prevents re-loading if the view is already showing the docs URL —
        // avoids a reload every time SwiftUI re-evaluates the view tree.
        guard webView.url?.absoluteString != docsURL.absoluteString else { return }
        var request = URLRequest(url: docsURL)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        webView.load(request)
    }
}
