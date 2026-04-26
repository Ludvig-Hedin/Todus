import Foundation

/// Shared HTTP metadata for native apps so the backend can distinguish clients (e.g. active sessions).
public enum TodusHTTPClient {
    /// `X-Todus-Platform` — consumed by `/api/trpc/sessions.list` metadata upsert.
    public static var platformHeaderValue: String {
        #if os(macOS)
        "macos"
        #elseif os(iOS)
        "ios"
        #else
        "native"
        #endif
    }

    public static func applyDefaultHeaders(to request: inout URLRequest) {
        request.setValue(platformHeaderValue, forHTTPHeaderField: "X-Todus-Platform")
    }
}
