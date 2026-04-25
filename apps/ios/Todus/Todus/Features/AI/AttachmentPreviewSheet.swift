import Photos
import SwiftUI
import UIKit

/// Full-screen preview for a chat attachment with save / copy for images and share for other files.
struct AttachmentPreviewSheet: View {
    let filename: String
    let onDismiss: () -> Void

    @State private var image: UIImage?
    @State private var imageLoadFailed = false
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var showStatusAlert = false

    private var fileURL: URL { AttachmentService.shared.url(for: filename) }
    private var isImage: Bool { AttachmentService.shared.isImageFile(filename) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .tint(.white)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if isImage, image != nil {
                        Button {
                            copyImageToPasteboard()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .tint(.white)
                        .disabled(isSaving)

                        Button {
                            saveImageToPhotos()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .tint(.white)
                        .disabled(isSaving)
                    } else if !isImage, FileManager.default.fileExists(atPath: fileURL.path) {
                        ShareLink(item: fileURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.white)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .alert("Todus", isPresented: $showStatusAlert) {
            Button("OK", role: .cancel) {
                showStatusAlert = false
            }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isImage, let image {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        } else if isImage, imageLoadFailed {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Couldn’t load image")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        } else if isImage {
            ProgressView()
                .tint(.white)
        } else {
            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text(AttachmentService.shared.friendlyAttachmentLabel(
                    filename: filename,
                    index: 0,
                    total: 1
                ))
                .font(.headline)
                .foregroundStyle(.white)
            }
        }
    }

    private func load() {
        guard isImage else { return }
        let loaded = AttachmentService.shared.loadImage(for: filename)
        image = loaded
        imageLoadFailed = (loaded == nil)
    }

    private func showStatus(_ text: String) {
        statusMessage = text
        showStatusAlert = true
    }

    private func copyImageToPasteboard() {
        guard let image else { return }
        UIPasteboard.general.image = image
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func saveImageToPhotos() {
        guard let image else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            let allowed = status == .authorized || status == .limited
            guard allowed else {
                Task { @MainActor in
                    isSaving = false
                    showStatus("Enable photo access in Settings to save images.")
                }
                return
            }
            Task { @MainActor in
                performSaveToLibrary(image: image)
            }
        }
    }

    private func performSaveToLibrary(image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            Task { @MainActor in
                isSaving = false
                if success {
                    showStatus("Saved to Photos")
                } else {
                    showStatus("Couldn’t save to Photos. Try again.")
                }
            }
        }
    }
}
