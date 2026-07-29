import SwiftUI

struct FurniturePropertiesPanel: View {
    @ObservedObject var viewModel: RoomViewerViewModel

    var body: some View {
        ScrollView {
            if let furniture = viewModel.selectedFurniture {
                VStack(alignment: .leading, spacing: 26) {
                    header(furniture)
                    dimensions(furniture)
                    position(furniture)
                    rotation(furniture)
                    metadata(furniture)
                }
                .padding(22)
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
        }
    }

    private func dimensions(_ furniture: FurnitureItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Dimensions")
            propertySlider(
                title: "Width",
                value: furniture.width,
                range: 0.3...3.5,
                onChange: { viewModel.updateSelected(width: $0) }
            )
            propertySlider(
                title: "Depth",
                value: furniture.depth,
                range: 0.3...3.0,
                onChange: { viewModel.updateSelected(depth: $0) }
            )
            propertySlider(
                title: "Height",
                value: furniture.height,
                range: 0.2...2.5,
                onChange: { viewModel.updateSelected(height: $0) }
            )
        }
    }

    private func position(_ furniture: FurnitureItem) -> some View {
        let position = viewModel.positionMeters(for: furniture)
        return VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Floor position")
            propertySlider(
                title: "Left / right",
                value: position.x,
                range: (-viewModel.scene.roomWidth / 2)...(viewModel.scene.roomWidth / 2),
                onChange: { viewModel.updateSelected(positionX: $0) }
            )
            propertySlider(
                title: "Front / back",
                value: position.z,
                range: (-viewModel.scene.roomDepth / 2)...(viewModel.scene.roomDepth / 2),
                onChange: { viewModel.updateSelected(positionZ: $0) }
            )
        }
    }

    private func rotation(_ furniture: FurnitureItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Orientation")
            HStack {
                Image(systemName: "rotate.right")
                    .foregroundStyle(AppTheme.accent)
                Slider(
                    value: Binding(
                        get: { furniture.rotationDegrees },
                        set: { viewModel.updateSelected(rotationDegrees: $0) }
                    ),
                    in: 0...360,
                    step: 1
                )
                .tint(AppTheme.accent)
                Text("\(Int(furniture.rotationDegrees))°")
                    .font(.caption.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }
        }
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

    private func propertySlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))) + " m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range
            )
            .tint(AppTheme.accent)
        }
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
