import AuthenticationServices

/// Async wrapper around ASAuthorizationControllerDelegate.
/// Bridges the delegate-based Apple Sign In API to Swift concurrency.
///
/// Marked @unchecked Sendable because the continuation is accessed from two contexts:
/// - Set inside withCheckedThrowingContinuation (caller's context)
/// - Read from delegate callbacks (system background queue)
/// This is safe because the set always happens-before the read (the system only fires
/// delegate callbacks after performRequests() is called, which is after the continuation is stored).
final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, @unchecked Sendable {
    /// nonisolated(unsafe) because this is accessed from both the caller's context
    /// (when set inside withCheckedThrowingContinuation) and the system's delegate
    /// callback queue (when read in didCompleteWithAuthorization/didCompleteWithError).
    /// The access pattern is safe: write once → read once, with a happens-before guarantee
    /// from the ASAuthorizationController lifecycle.
    nonisolated(unsafe) private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Bridges ASAuthorizationController's delegate-based API to async/await.
    /// The continuation body runs on the caller's isolation context (typically MainActor),
    /// but delegate callbacks run on a system queue — this is safe because
    /// continuation.resume() is Sendable and the property access is sequenced.
    func performRequest(controller: ASAuthorizationController) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthService.AuthError.invalidResponse)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
