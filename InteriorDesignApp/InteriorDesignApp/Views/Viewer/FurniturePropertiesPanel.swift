import SwiftUI

struct FurniturePropertiesPanel: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    var onClose: (() -> Void)?

    @State private var showsMoveControls = false

    init(viewModel: RoomViewerViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            if let furniture = viewModel.selectedFurniture {
                VStack(alignment: .leading, spacing: 16) {
                    header(furniture)
                    actions
                    if showsMoveControls {
                        moveControls
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    metadata(furniture)
                }
                .padding(18)
            } else {
                ContentUnavailableView(
                    "Select furniture",
                    systemImage: "chair.lounge",
                    description: Text("Choose an object in the room to inspect its properties.")
                )
                .padding(28)
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.line)
        }
    }

    private func header(_ furniture: FurnitureItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: furniture.category.systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color(hex: furniture.colorHex).gradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(furniture.name)
                    .font(.headline)
                Text(furniture.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Close properties")
            }
        }
    }

    private var actions: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            actionButton("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                showsMoveControls.toggle()
            }
            actionButton("Rotate", systemImage: "rotate.right") {
                viewModel.rotateSelected()
            }
            actionButton("Replace", systemImage: "arrow.triangle.2.circlepath") {
                viewModel.replaceSelectedWithNextCategory()
            }
            actionButton("Duplicate", systemImage: "plus.square.on.square") {
                viewModel.duplicateSelected()
            }
            actionButton("Delete", systemImage: "trash", role: .destructive) {
                viewModel.deleteSelected()
            }
        }
    }

    private var moveControls: some View {
        HStack(spacing: 8) {
            moveButton("arrow.left", x: -0.025, y: 0)
            moveButton("arrow.up", x: 0, y: -0.025)
            moveButton("arrow.down", x: 0, y: 0.025)
            moveButton("arrow.right", x: 0.025, y: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func metadata(_ furniture: FurnitureItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Scene data")
            if let confidence = furniture.detectorConfidence {
                infoRow("Detection", value: "\(Int(confidence * 100))%")
            }
            infoRow("Geometry", value: "RealityKit box")
            infoRow("Mesh", value: furniture.meshReference ?? "Not connected")
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
    }

    private func moveButton(_ systemImage: String, x: Double, y: Double) -> some View {
        Button {
            viewModel.moveSelected(normalizedX: x, normalizedY: y)
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(AppTheme.secondaryInk)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
    }
}
