import PhotosUI
import SwiftUI

struct CaptureMethodView: View {
    @ObservedObject var viewModel: CaptureMethodViewModel
    let onBack: () -> Void
    let onRecordScan: () -> Void
    let onUsePhotos: () -> Void
    let onUseSample: () -> Void
    let onVideoSelected: (RoomScanVideo) -> Void

    @State private var isVideoPickerPresented = false
    @State private var videoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            navigation

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan your room")
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                        Text("Choose how you’d like to create your editable room.")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    VStack(spacing: 14) {
                        captureOption(
                            title: "Record room scan",
                            subtitle: "Recommended",
                            systemImage: "video.fill",
                            isPrimary: true,
                            action: onRecordScan
                        )
                        captureOption(
                            title: viewModel.isImportingVideo ? "Importing video…" : "Upload room video",
                            subtitle: "Choose an existing walkthrough",
                            systemImage: "square.and.arrow.down",
                            action: { isVideoPickerPresented = true }
                        )
                        .disabled(viewModel.isImportingVideo)
                        captureOption(
                            title: "Use photos",
                            subtitle: "Quick estimate",
                            systemImage: "photo.on.rectangle.angled",
                            action: onUsePhotos
                        )
                        captureOption(
                            title: "Try a sample room",
                            subtitle: "Explore without capturing",
                            systemImage: "cube.transparent",
                            action: onUseSample
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .photosPicker(
            isPresented: $isVideoPickerPresented,
            selection: $videoPickerItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: videoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let video = await viewModel.importVideo(from: item) {
                    onVideoSelected(video)
                }
                videoPickerItem = nil
            }
        }
        .alert(
            "Video unavailable",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private var navigation: some View {
        HStack {
            CircleIconButton(systemImage: "chevron.left", action: onBack)
            Spacer()
            Text("New room")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(18)
    }

    private func captureOption(
        title: String,
        subtitle: String,
        systemImage: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 50, height: 50)
                    .background(isPrimary ? Color.white.opacity(0.16) : AppTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.76) : AppTheme.secondaryInk)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .opacity(0.7)
            }
            .padding(16)
            .foregroundStyle(isPrimary ? Color.white : AppTheme.ink)
            .background(isPrimary ? AppTheme.ink : Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isPrimary ? Color.clear : AppTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
