import SwiftUI

enum AppTheme {
    static let background = Color(hex: "F4F3EF")
    static let surface = Color.white.opacity(0.82)
    static let ink = Color(hex: "1D1D1F")
    static let secondaryInk = Color(hex: "6E6E73")
    static let accent = Color(hex: "6D735F")
    static let line = Color.black.opacity(0.075)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func premiumCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.055), radius: 24, y: 12)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .fontWeight(.semibold)
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.thinMaterial)
                .clipShape(Circle())
                .overlay { Circle().stroke(AppTheme.line) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ink)
    }
}

