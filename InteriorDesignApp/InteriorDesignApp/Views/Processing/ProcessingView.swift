import SwiftUI

struct ProcessingView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    let onCancel: () -> Void
    let onComplete: (RoomScene) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            processingBackground

            AppTheme.background.opacity(0.82)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                Spacer()

                VStack(alignment: .leading, spacing: 9) {
                    Text(viewModel.isVideoProcessing ? "Reconstructing your room" : "Understanding your room")
                        .font(.title.bold())
                        .fontDesign(.rounded)
                    Text(viewModel.isVideoProcessing
                         ? "Preparing an editable space from your walkthrough"
                         : "Creating an editable space from your photo")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryInk)
                    if viewModel.isVideoProcessing {
                        Text("Backend job · sample normalized scene output")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                        analysisRow(step: step, index: index)
                    }
                }
                .padding(14)
                .premiumCard(cornerRadius: 26)

                ProgressView(value: viewModel.analysisProgress)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Room analysis progress")
                    .accessibilityValue("\(Int(viewModel.analysisProgress * 100)) percent")

                if case let .failed(message) = viewModel.analysisState {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)

                        Button("Retry") {
                            viewModel.retry()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .accessibilityHint("Uploads the room scan again")
                    }
                    .transition(.opacity)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 620)
        }
        .onAppear {
            viewModel.start(onComplete: onComplete)
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    @ViewBuilder
    private var processingBackground: some View {
        if let photo = viewModel.selectedPhoto {
            GeometryReader { proxy in
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .blur(radius: 28)
                    .opacity(0.16)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()
            .clipped()
        } else {
            LinearGradient(
                colors: [AppTheme.background, AppTheme.accent.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    private func analysisRow(step: AnalysisStep, index: Int) -> some View {
        let isCompleted = index < viewModel.completedStepCount
        let isActive = index == viewModel.completedStepCount && viewModel.analysisState == .analyzing

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isCompleted ? AppTheme.accent : AppTheme.line)
                    .frame(width: 30, height: 30)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else if isActive {
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 7, height: 7)
                        }
                        .transition(.opacity)
                }
            }

            Text(step.title)
                .font(.body.weight(isCompleted || isActive ? .semibold : .regular))
                .foregroundStyle(isCompleted || isActive ? AppTheme.ink : AppTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isActive {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85),
            value: viewModel.completedStepCount
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCompleted ? "Complete" : isActive ? "In progress" : "Waiting")
    }
}
