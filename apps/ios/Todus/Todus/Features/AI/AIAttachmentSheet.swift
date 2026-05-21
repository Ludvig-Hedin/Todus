import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Bottom sheet presented when the user taps the plus button in the AI chat input.
/// Shows a horizontal photo strip (camera + recent photos), upload rows for images
/// and files, and toggles for the AI's connected sources.
///
/// Replaces the small popover menu that previously sat above the + button. Uses
/// `.thinMaterial` so the system's sheet container reads as a translucent glass
/// surface over the chat below — matches iOS 26 sheet aesthetics on older OSes
/// and lets the system render full liquid glass on iOS 26+.
struct AIAttachmentSheet: View {
    @Bindable var chatService: AIChatService

    var onOpenCamera: () -> Void
    var onOpenPhotoLibrary: () -> Void
    var onOpenFilePicker: () -> Void
    var onAttachImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var recentAssets: [PHAsset] = []
    @State private var photoAuthStatus: PHAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            sourcesHeader
            photoStrip
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 20)

            uploadSection
                .padding(.vertical, 4)

            Divider()
                .padding(.horizontal, 20)

            togglesSection
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .padding(.bottom, 8)
        .onAppear { requestAndLoadPhotos() }
    }

    // MARK: - Header

    private var sourcesHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sources")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                dismiss()
                // Defer so the sheet finishes dismissing before the system
                // PhotosPicker tries to come up (avoids stacked-presentation glitches).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onOpenPhotoLibrary()
                }
            } label: {
                Text("All Photos")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Photo strip

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cameraTile

                if photoAuthStatus == .authorized || photoAuthStatus == .limited {
                    ForEach(recentAssets, id: \.localIdentifier) { asset in
                        PhotoThumbnail(asset: asset) { image in
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onAttachImage(image)
                            }
                        }
                    }
                } else if photoAuthStatus == .denied || photoAuthStatus == .restricted {
                    photoAccessDeniedTile
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var cameraTile: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onOpenCamera()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: "camera")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .frame(width: 110, height: 110)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take photo")
    }

    private var photoAccessDeniedTile: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("Allow access")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 110, height: 110)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Upload section

    private var uploadSection: some View {
        VStack(spacing: 0) {
            uploadRow(
                icon: "photo.badge.plus",
                title: "Upload image",
                subtitle: "From your photo library"
            ) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onOpenPhotoLibrary()
                }
            }
            uploadRow(
                icon: "doc.badge.plus",
                title: "Upload file",
                subtitle: "Documents, PDFs, and more"
            ) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onOpenFilePicker()
                }
            }
        }
    }

    private func uploadRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggles section

    private var togglesSection: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "Calendar",
                subtitle: "Read upcoming events",
                isOn: Binding(
                    get: { chatService.aiCanReadCalendar },
                    set: { chatService.aiCanReadCalendar = $0 }
                )
            ) {
                AppleCalendarIconView(size: 32)
            }
            toggleRow(
                title: "Web search",
                subtitle: "Search the internet",
                isOn: Binding(
                    get: { chatService.aiCanWebSearch },
                    set: { chatService.aiCanWebSearch = $0 }
                )
            ) {
                ZStack {
                    Circle().fill(Color(.systemGray5))
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .frame(width: 32, height: 32)
            }
            toggleRow(
                title: "Gmail",
                subtitle: "Read your inbox",
                isOn: Binding(
                    get: { chatService.aiCanReadEmail },
                    set: { chatService.aiCanReadEmail = $0 }
                )
            ) {
                GmailIconView(size: 32)
            }
        }
    }

    private func toggleRow<Icon: View>(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .accessibilityLabel("\(title): \(subtitle)")
                .tint(.green)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Photos library

    private func requestAndLoadPhotos() {
        // PHAsset thumbnail access requires .readWrite — there is no read-only level
        // on iOS 14+. .addOnly would let us write but not enumerate the library.
        // If we ever drop in-sheet thumbnail browsing in favor of PHPickerViewController,
        // this whole permission prompt can go away.
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoAuthStatus = current
        if current == .authorized || current == .limited {
            loadRecentAssets()
            return
        }
        if current == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    photoAuthStatus = status
                    if status == .authorized || status == .limited {
                        loadRecentAssets()
                    }
                }
            }
        }
    }

    private func loadRecentAssets() {
        Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 24
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            await MainActor.run { self.recentAssets = assets }
        }
    }
}

// MARK: - PhotoThumbnail

private struct PhotoThumbnail: View {
    let asset: PHAsset
    var onTap: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var isLoadingFullSize = false
    @State private var loadErrorMessage: String?

    /// Shared caching manager — reused across thumbnails so prefetched assets
    /// don't get re-decoded each time the strip rebuilds.
    private static let manager = PHCachingImageManager()

    var body: some View {
        Button {
            guard !isLoadingFullSize else { return }
            requestFullSize()
        } label: {
            ZStack(alignment: .topTrailing) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 110, height: 110)
                }

                // Selection circle in top-right — visual cue matching the design.
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .background(Circle().fill(Color.black.opacity(0.20)))
                    .frame(width: 22, height: 22)
                    .padding(8)

                if isLoadingFullSize {
                    ZStack {
                        Color.black.opacity(0.25)
                        ProgressView().tint(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(width: 110, height: 110)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
        .alert(
            "Couldn't load photo",
            isPresented: Binding(
                get: { loadErrorMessage != nil },
                set: { if !$0 { loadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                loadErrorMessage = nil
            }
        } message: {
            Text(loadErrorMessage ?? "The selected photo is no longer available.")
        }
    }

    private func loadThumbnail() {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        Self.manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: opts
        ) { result, _ in
            guard let result else { return }
            Task { @MainActor in self.image = result }
        }
    }

    private func requestFullSize() {
        isLoadingFullSize = true
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .none
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        Self.manager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: opts
        ) { result, info in
            // Skip the low-res "degraded" delivery so we don't fire onTap twice.
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
            Task { @MainActor in
                isLoadingFullSize = false
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    return
                }
                if let result {
                    onTap(result)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    loadErrorMessage = error.localizedDescription
                } else {
                    loadErrorMessage = "The selected photo could not be loaded."
                }
            }
        }
    }
}
