import Foundation

/// Prevents URLSession from following redirects, so we can inspect 3xx responses directly.
/// Used for Apple sign-in where Better-Auth may return a redirect with the token.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Check if the redirect URL contains our token (Better-Auth redirect-with-token pattern)
        if let redirectURL = request.url,
           let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false),
           components.queryItems?.contains(where: { $0.name == "token" }) == true {
            // Don't follow — we'll extract the token from the redirect Location
            completionHandler(nil)
        } else {
            // Follow non-token redirects (e.g., OAuth provider redirects)
            completionHandler(request)
        }
    }
}
