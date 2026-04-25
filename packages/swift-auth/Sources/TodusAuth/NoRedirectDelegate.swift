import Foundation

/// Prevents URLSession from following redirects, so auth bridge calls can inspect the
/// initial 3xx response directly (Location headers, Set-Cookie, set-auth-token, etc.).
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Always stop at the first redirect. Callers intentionally use this delegate when
        // they need access to the original 3xx response instead of the final destination.
        completionHandler(nil)
    }
}
