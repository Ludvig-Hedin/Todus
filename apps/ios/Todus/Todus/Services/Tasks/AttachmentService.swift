import Foundation
import ImageIO
import UIKit

/// Manages local file storage for task attachments.
/// Saves images and files to the app's Documents/Attachments directory
/// and returns unique filenames that can be stored in TaskRecord.attachmentNames.
final class AttachmentService: @unchecked Sendable {
    /// Shared singleton instance — no state, just file I/O helpers
    static let shared = AttachmentService()

    private let attachmentsDir: URL
    private let thumbnailCache = NSCache<NSString, UIImage>()

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

    /// Returns UIImage for an attachment if it's a supported image format
    func loadImage(for filename: String) -> UIImage? {
        let fileURL = url(for: filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    func isImageFile(_ filename: String) -> Bool {
        let ext = url(for: filename).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"].contains(ext)
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
        return image
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
        thumbnailCache.removeAllObjects()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
