import SwiftUI

struct RoomCanvasView: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    let onSelection: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let roomWidth = max(proxy.size.width - 56, 1)
            let roomHeight = max(proxy.size.height - 56, 1)
            let pointsPerMeter = min(
                roomWidth / viewModel.scene.roomWidth,
                roomHeight / viewModel.scene.roomDepth
            )
            let fittedWidth = viewModel.scene.roomWidth * pointsPerMeter
            let fittedHeight = viewModel.scene.roomDepth * pointsPerMeter

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: "E8E4DC"))
                    .overlay { roomGrid }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(hex: "BDB7AC"), lineWidth: 5)
                    }
                    .frame(width: fittedWidth, height: fittedHeight)

                ForEach(viewModel.scene.furniture) { furniture in
                    FurnitureBoxView(
                        furniture: furniture,
                        isSelected: viewModel.selectedFurnitureID == furniture.id,
                        pointsPerMeter: pointsPerMeter
                    )
                    .position(
                        x: (proxy.size.width - fittedWidth) / 2 + CGFloat(furniture.normalizedX) * fittedWidth,
                        y: (proxy.size.height - fittedHeight) / 2 + CGFloat(furniture.normalizedY) * fittedHeight
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            viewModel.select(furniture)
                            onSelection()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 460)
        .background(Color(hex: "F8F7F4"))
    }

    private var roomGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            var path = Path()
            stride(from: spacing, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: spacing, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.black.opacity(0.035)), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct FurnitureBoxView: View {
    let furniture: FurnitureItem
    let isSelected: Bool
    let pointsPerMeter: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: furniture.colorHex).gradient)
            Image(systemName: furniture.category.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(
            width: max(CGFloat(furniture.width) * pointsPerMeter, 28),
            height: max(CGFloat(furniture.depth) * pointsPerMeter, 28)
        )
        .rotationEffect(.degrees(furniture.rotationDegrees))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                .padding(-4)
        }
        .shadow(
            color: isSelected ? AppTheme.accent.opacity(0.38) : Color.black.opacity(0.13),
            radius: isSelected ? 13 : 5,
            y: isSelected ? 5 : 3
        )
        .scaleEffect(isSelected ? 1.035 : 1)
        .accessibilityLabel(furniture.name)
    }
}

