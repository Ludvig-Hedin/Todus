import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Manages local file storage for task attachments.
/// Saves images and files to the app's Documents/Attachments directory
/// and returns unique filenames that can be stored in TaskRecord.attachmentNames.
final class AttachmentService: @unchecked Sendable {
    /// Shared singleton instance — no state, just file I/O helpers
    static let shared = AttachmentService()

    private let attachmentsDir: URL
    private let thumbnailCache = NSCache<NSString, UIImage>()
    /// Tracks the cache keys we've used per filename so a delete can evict only the
    /// affected variants rather than wiping the entire cache. Keyed by attachment
    /// filename → the set of `"<filename>-<maxPixelSize>"` keys created for it.
    private var thumbnailKeysByFilename: [String: Set<NSString>] = [:]
    private let thumbnailKeysLock = NSLock()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        attachmentsDir = docs.appendingPathComponent("Attachments", isDirectory: true)
        // Ensure the directory exists on first use
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
    }

    /// Returns the on-disk URL for a given attachment filename
    func url(for filename: String) -> URL {
        attachmentsDir.appendingPathComponent(filename)
    }

    /// Preferred MIME type for a stored filename (used when uploading to the AI backend).
    /// Uses the extension when possible, then sniffs common image magics so vision models
    /// still receive `image/*` if the file is JPEG/PNG but the extension is wrong.
    func mimeType(for filename: String) -> String {
        let ext = url(for: filename).pathExtension.lowercased()
        if let ut = UTType(filenameExtension: ext), let mime = ut.preferredMIMEType {
            return mime
        }
        return mimeTypeBySniffingFileHeader(for: filename) ?? (isImageFile(filename) ? "image/jpeg" : "application/octet-stream")
    }

    private func firstBytesOfFile(at fileURL: URL, max: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: max)
    }

    private func mimeTypeBySniffingFileHeader(for filename: String) -> String? {
        let fileURL = url(for: filename)
        guard let data = firstBytesOfFile(at: fileURL, max: 32), data.count >= 12 else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if data.prefix(6).starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if data.count >= 12, data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP" {
            return "image/webp"
        }
        return nil
    }

    /// Returns UIImage for an attachment if it's a supported image format
    func loadImage(for filename: String) -> UIImage? {
        let fileURL = url(for: filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    func isImageFile(_ filename: String) -> Bool {
        let ext = url(for: filename).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "ico"].contains(ext) {
            return true
        }
        return mimeTypeBySniffingFileHeader(for: filename)?.hasPrefix("image/") == true
    }

    /// Short label for the chat UI (avoids full UUID filenames).
    func friendlyAttachmentLabel(filename: String, index: Int, total: Int) -> String {
        if isImageFile(filename) {
            if total <= 1 { return "Image" }
            return "Image \(index + 1)"
        }
        let ext = url(for: filename).pathExtension.uppercased()
        let tag = ext.isEmpty ? "FILE" : ext
        if total <= 1 { return "File (\(tag))" }
        return "File \(index + 1) (\(tag))"
    }

    func loadThumbnail(for filename: String, maxPixelSize: CGFloat) -> UIImage? {
        guard isImageFile(filename) else { return nil }

        let cacheKey = "\(filename)-\(Int(maxPixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.attachmentDecode,
            message: "AttachmentService.loadThumbnail begin filename=\(filename)"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.attachmentDecode,
                trace,
                message: "AttachmentService.loadThumbnail end filename=\(filename)"
            )
        }

        let fileURL = url(for: filename)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(image, forKey: cacheKey)
        rememberThumbnailKey(cacheKey, for: filename)
        return image
    }

    private func rememberThumbnailKey(_ key: NSString, for filename: String) {
        thumbnailKeysLock.lock()
        defer { thumbnailKeysLock.unlock() }
        thumbnailKeysByFilename[filename, default: []].insert(key)
    }

    func importFile(at url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { [url] in
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            return AttachmentService.shared.saveData(data, fileExtension: ext)
        }.value
    }

    /// Saves JPEG image data to disk, returns the unique filename
    @discardableResult
    func saveImage(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = attachmentsDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            return nil
        }
    }

    /// Saves raw data to disk with a given extension, returns the unique filename
    @discardableResult
    func saveData(_ data: Data, fileExtension: String) -> String? {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let fileURL = attachmentsDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            return nil
        }
    }

    /// Deletes an attachment file
    func delete(filename: String) {
        let fileURL = url(for: filename)
        // Only evict cached thumbnails for THIS filename. A single attachment delete
        // shouldn't invalidate every other attachment's cached thumbnail.
        thumbnailKeysLock.lock()
        let keys = thumbnailKeysByFilename.removeValue(forKey: filename) ?? []
        thumbnailKeysLock.unlock()
        for key in keys {
            thumbnailCache.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
