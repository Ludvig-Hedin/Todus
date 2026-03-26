import Foundation
import UIKit

/// Manages local file storage for task attachments.
/// Saves images and files to the app's Documents/Attachments directory
/// and returns unique filenames that can be stored in TaskRecord.attachmentNames.
final class AttachmentService: @unchecked Sendable {
    /// Shared singleton instance — no state, just file I/O helpers
    static let shared = AttachmentService()

    private let attachmentsDir: URL

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
        try? FileManager.default.removeItem(at: fileURL)
    }
}
