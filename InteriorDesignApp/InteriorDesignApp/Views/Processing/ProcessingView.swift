import SwiftUI

struct ProcessingView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    let onCancel: () -> Void
    let onComplete: (RoomScene) -> Void

    var body: some View {
        VStack(spacing: 38) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(AppTheme.line, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accent, Color(hex: "B8A27C"), AppTheme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 174, height: 174)
            .shadow(color: AppTheme.accent.opacity(0.14), radius: 32)

            VStack(spacing: 10) {
                Text("Creating \(viewModel.room.name)")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(viewModel.stage)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .contentTransition(.opacity)
            }

            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Double(index + 1) / 4.0 <= viewModel.progress ? AppTheme.accent : AppTheme.line)
                        .frame(width: index == Int(viewModel.progress * 4) ? 30 : 12, height: 6)
                }
            }
            .animation(.easeInOut, value: viewModel.progress)

            Spacer()

            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.secondaryInk)
                .padding(.bottom, 26)
        }
        .padding(24)
        .onAppear {
            viewModel.start(onComplete: onComplete)
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
}

