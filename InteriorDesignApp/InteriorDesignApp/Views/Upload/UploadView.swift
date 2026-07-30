import PhotosUI
import SwiftUI

struct UploadView: View {
    @ObservedObject var viewModel: UploadViewModel
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isPhotoPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            navigation

            Group {
                if let photo = viewModel.selectedPhoto {
                    selectedPhotoView(photo)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    emptySelectionView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.selectedPhoto?.id)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $pickerItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await viewModel.importPhoto(from: newItem)
                pickerItem = nil
            }
        }
        .alert(
            "Photo unavailable",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            if viewModel.errorMessage?.contains("Settings") == true {
                Button("Open Settings") { openApplicationSettings() }
            }
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

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add your room")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
            Text("Choose a clear, wide photo so we can prepare your editable space.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptySelectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                title
                uploadCard
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 38)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var uploadCard: some View {
        VStack(spacing: 18) {
            if viewModel.isImporting {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                    .frame(width: 76, height: 76)
                    .accessibilityLabel("Importing room photo")
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 76, height: 76)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
            Text("Choose a room photo")
                .font(.headline)
            Text("JPEG, PNG, and HEIC images are supported")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
            Button("Browse photos", action: presentPhotoPicker)
                .buttonStyle(.bordered)
                .disabled(viewModel.isImporting)
                .accessibilityHint("Opens your photo library to select one room image")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundStyle(AppTheme.accent.opacity(0.32))
        }
    }

    private func selectedPhotoView(_ photo: SelectedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Selected Room")
                .font(.title.bold())
                .fontDesign(.rounded)

            GeometryReader { proxy in
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay {
                        if viewModel.isImporting {
                            ZStack {
                                Color.black.opacity(0.2)
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Importing replacement room photo")
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 10)
            .accessibilityLabel("Selected room photo")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    retakeButton
                    continueButton
                }

                VStack(spacing: 12) {
                    continueButton
                    retakeButton
                }
            }
            .disabled(viewModel.isImporting)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var retakeButton: some View {
        Button("Retake", action: presentPhotoPicker)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(AppTheme.ink)
            .background(Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var continueButton: some View {
        PrimaryButton(
            title: "Continue",
            systemImage: "arrow.right",
            action: onContinue
        )
    }

    private func presentPhotoPicker() {
        Task {
            if await viewModel.prepareForPhotoSelection() {
                isPhotoPickerPresented = true
            }
        }
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
