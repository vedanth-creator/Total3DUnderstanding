import SwiftUI

struct RoomViewerView: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    let onClose: () -> Void

    @State private var showCompactProperties = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                toolbar

                if proxy.size.width >= 820 {
                    HStack(spacing: 18) {
                        viewerCanvas
                        FurniturePropertiesPanel(viewModel: viewModel)
                            .frame(width: 340)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                    viewerCanvas
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .sheet(isPresented: $showCompactProperties) {
            FurniturePropertiesPanel(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            CircleIconButton(systemImage: "xmark", action: onClose)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.scene.name)
                    .font(.headline)
                Text("Editable preview")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()
            Button {
                showCompactProperties = true
            } label: {
                Label("Properties", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
    }

    private var viewerCanvas: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Top view", systemImage: "square.3.layers.3d.top.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                Text("Tap an object to edit")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(16)

            RoomCanvasView(viewModel: viewModel) {
                showCompactProperties = true
            }
        }
        .premiumCard(cornerRadius: 26)
    }
}

