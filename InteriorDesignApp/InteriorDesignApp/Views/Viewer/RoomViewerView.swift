import SwiftUI

struct RoomViewerView: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    let onClose: () -> Void

    @State private var showCompactProperties = false
    @State private var resetViewToken = 0

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
                    ZStack(alignment: .bottom) {
                        viewerCanvas
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        if showCompactProperties {
                            FurniturePropertiesPanel(
                                viewModel: viewModel,
                                onClose: { showCompactProperties = false }
                            )
                            .frame(maxHeight: min(proxy.size.height * 0.36, 290))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)
                            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(2)
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showCompactProperties)
        .onChange(of: viewModel.selectedFurnitureID) { _, selectedID in
            if selectedID == nil {
                showCompactProperties = false
            }
        }
        .onAppear {
            AppDebugLog.write("Room viewer appeared; scene=\(viewModel.scene.id)")
        }
        .onDisappear {
            AppDebugLog.write("Room viewer disappeared; scene=\(viewModel.scene.id)")
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
                Label("3D room", systemImage: "cube.transparent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                Button {
                    resetViewToken += 1
                } label: {
                    Label("Reset View", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            RealityRoomView(
                viewModel: viewModel,
                resetViewToken: resetViewToken
            ) {
                showCompactProperties = true
            }
        }
        .premiumCard(cornerRadius: 26)
    }
}
