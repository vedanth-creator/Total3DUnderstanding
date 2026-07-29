import SwiftUI

struct UploadView: View {
    @ObservedObject var viewModel: UploadViewModel
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            navigation

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    title
                    uploadCard
                    samplePicker
                    PrimaryButton(
                        title: "Create editable room",
                        systemImage: "sparkles",
                        action: onContinue
                    )
                    .disabled(viewModel.selectedRoom == nil)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 38)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Start with a clear, wide photo. For now, choose a sample to explore the complete experience.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var uploadCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 76, height: 76)
                .background(AppTheme.accent.opacity(0.1))
                .clipShape(Circle())
            Text("Choose a room photo")
                .font(.headline)
            Text("Photo import will connect here in a later build")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
            Button("Browse photos") { }
                .buttonStyle(.bordered)
                .disabled(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundStyle(AppTheme.accent.opacity(0.32))
        }
    }

    private var samplePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Or use a sample")
                .font(.headline)

            ForEach(viewModel.availableRooms) { room in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        viewModel.select(room)
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: room.systemImage)
                            .font(.title3)
                            .foregroundStyle(Color(hex: room.accentHex))
                            .frame(width: 50, height: 50)
                            .background(Color(hex: room.accentHex).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.name)
                                .font(.subheadline.weight(.semibold))
                            Text(room.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: viewModel.selectedRoom == room ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(viewModel.selectedRoom == room ? AppTheme.accent : AppTheme.secondaryInk.opacity(0.35))
                    }
                    .padding(14)
                    .background(viewModel.selectedRoom == room ? Color.white : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

