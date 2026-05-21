import XCTest
@testable import Todus

/// Targets `AvatarDiskCache`, the on-disk SHA-256-keyed avatar store that
/// replaced a per-launch-randomized `String.hashValue` cache key. The previous
/// behaviour orphaned every cached image on each cold launch — these tests
/// pin the stable-key contract that the disk cache depends on.
final class AppThemeAvatarCacheTests: XCTestCase {
    func testSHA256KeyIsStableAcrossCalls() {
        let url = "https://example.com/avatars/u/abc.jpg"
        let k1 = AvatarDiskCache.key(for: url)
        let k2 = AvatarDiskCache.key(for: url)

        XCTAssertEqual(k1, k2, "Same input must always produce the same key (SHA-256 is deterministic).")
        // SHA-256 hex digest is 64 lowercase hex chars.
        XCTAssertEqual(k1.count, 64)
        XCTAssertTrue(k1.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testDifferentURLsProduceDifferentKeys() {
        let k1 = AvatarDiskCache.key(for: "https://example.com/a.jpg")
        let k2 = AvatarDiskCache.key(for: "https://example.com/b.jpg")
        let k3 = AvatarDiskCache.key(for: "https://example.com/a.jpg?v=2")

        XCTAssertNotEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
        XCTAssertNotEqual(k2, k3)
    }

    func testEmptyStringYieldsStableKey() {
        // Edge case: the production guard at the call site filters empty strings
        // out, but the disk-cache helper itself must not crash.
        let k1 = AvatarDiskCache.key(for: "")
        let k2 = AvatarDiskCache.key(for: "")
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 64)
    }

    func testWriteThenReadRoundTrip() throws {
        // Use a randomized URL so parallel test runs don't collide on the same
        // cache file.
        let url = "https://test.example.invalid/\(UUID().uuidString).jpg"
        let key = AvatarDiskCache.key(for: url)
        let payload = "avatar-bytes-\(UUID().uuidString)".data(using: .utf8)!

        addTeardownBlock {
            // Best-effort cleanup. The cache directory lives under
            // `Caches/avatars`, which iOS can evict, but explicit cleanup keeps
            // repeated test runs deterministic.
            try? FileManager.default.removeItem(at: AvatarDiskCache.url(for: key))
        }

        AvatarDiskCache.write(payload, key: key)
        let read = AvatarDiskCache.read(key: key)
        XCTAssertEqual(read, payload)
    }

    func testReadOfMissingKeyReturnsNil() {
        // Key that almost certainly hasn't been written. SHA of a UUID-derived
        // string keeps collisions astronomically unlikely.
        let key = AvatarDiskCache.key(for: "missing-\(UUID().uuidString)")
        XCTAssertNil(AvatarDiskCache.read(key: key))
    }

    func testKeyMatchesKnownSHA256Vector() {
        // Belt-and-suspenders pin: SHA-256("abc") is a well-known fixed digest.
        // If this changes we have a far bigger problem than avatar caching.
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertEqual(AvatarDiskCache.key(for: "abc"), expected)
    }
}
