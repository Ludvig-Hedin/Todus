//
//  ContentView.swift
//  Todus
//
//  Created by Ludvig Hedin on 2026-02-21.
//

import AuthenticationServices
import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    var body: some View {
        MailWebView(urlString: "https://todus-production.ludvighedin15.workers.dev/mail/inbox")
            .ignoresSafeArea(.container, edges: .bottom)
            .onOpenURL { url in
                NotificationCenter.default.post(name: .todusAuthCallback, object: url)
            }
    }
}

private extension Notification.Name {
    static let todusAuthCallback = Notification.Name("todusAuthCallback")
}

private struct MailWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "TodusNative/1.0"
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        context.coordinator.startObservers()

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op. Initial URL is loaded in makeUIView.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, ASWebAuthenticationPresentationContextProviding {
        weak var webView: WKWebView?

        private let googleAuthHosts: Set<String> = [
            "accounts.google.com",
            "oauth2.googleapis.com",
            "accounts.youtube.com",
            "myaccount.google.com",
        ]

        private let appCookieHosts = [
            "todus-production.ludvighedin15.workers.dev",
            "todus-server-v1-production.ludvighedin15.workers.dev",
            ".workers.dev",
        ]

        private var authSession: ASWebAuthenticationSession?
        private var foregroundObserver: NSObjectProtocol?
        private var callbackObserver: NSObjectProtocol?

        deinit {
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            if let callbackObserver {
                NotificationCenter.default.removeObserver(callbackObserver)
            }
        }

        func startObservers() {
            if foregroundObserver == nil {
                foregroundObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.willEnterForegroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.syncCookiesFromSharedStoreAndReload()
                }
            }

            if callbackObserver == nil {
                callbackObserver = NotificationCenter.default.addObserver(
                    forName: .todusAuthCallback,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let url = notification.object as? URL else { return }
                    self?.handleAuthCallback(url)
                }
            }
        }

        private func handleAuthCallback(_ url: URL) {
            guard url.scheme == "todus" else { return }
            authSession?.cancel()
            authSession = nil
            syncCookiesFromSharedStoreAndReload()
        }

        private func syncCookiesFromSharedStoreAndReload() {
            guard let webView else { return }
            let sharedCookies = HTTPCookieStorage.shared.cookies ?? []

            let targetCookies = sharedCookies.filter { cookie in
                appCookieHosts.contains(where: { host in
                    cookie.domain == host || cookie.domain.hasSuffix(host)
                })
            }

            guard !targetCookies.isEmpty else {
                webView.reload()
                return
            }

            let group = DispatchGroup()
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

            for cookie in targetCookies {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                webView.reload()
            }
        }

        private func startGoogleAuthSession(_ url: URL) {
            authSession?.cancel()

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "todus") {
                [weak self] callbackURL, _ in
                guard let self else { return }
                if callbackURL?.scheme == "todus" {
                    self.syncCookiesFromSharedStoreAndReload()
                    return
                }
                self.webView?.reload()
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session

            if !session.start() {
                UIApplication.shared.open(url)
            }
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if let host = url.host, googleAuthHosts.contains(host) {
                startGoogleAuthSession(url)
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme, scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
                return
            }

            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

#Preview {
    ContentView()
}
