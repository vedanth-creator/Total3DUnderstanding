import SwiftUI

struct ScanGuidanceOverlay: View {
    let guidance: [String]
    let progress: Double
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Room coverage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Mocked estimate")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(AppTheme.accent)
                .accessibilityValue("Mocked estimate, \(Int(progress * 100)) percent")

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .transition(.opacity)
            }

            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(guidance, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                }

                if let currentGuidance {
                    Text(currentGuidance)
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var currentGuidance: String? {
        guard !guidance.isEmpty else { return nil }
        let index = min(guidance.count - 1, Int(progress * Double(guidance.count)))
        guard guidance.indices.contains(index) else { return guidance.first }
        return guidance[index]
    }
}
