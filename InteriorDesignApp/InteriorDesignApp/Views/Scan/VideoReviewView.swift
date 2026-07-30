import AVKit
import SwiftUI

struct VideoReviewView: View {
    @ObservedObject var viewModel: VideoReviewViewModel
    let onRetake: () -> Void
    let onUseVideo: (RoomScanVideo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review room scan")
                    .font(.headline)
                Spacer()
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 18) {
                GeometryReader { proxy in
                    VideoPlayer(player: viewModel.player)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
                .accessibilityLabel("Room scan video preview")

                HStack {
                    Label(viewModel.durationText, systemImage: "clock")
                    Spacer()
                    Text(viewModel.detailsText)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .font(.caption.weight(.medium))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        retakeButton
                        useButton
                    }
                    VStack(spacing: 12) {
                        useButton
                        retakeButton
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await viewModel.preparePreview()
        }
        .onDisappear {
            viewModel.pause()
        }
    }

    private var retakeButton: some View {
        Button("Retake") {
            viewModel.discardVideo()
            onRetake()
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .foregroundStyle(AppTheme.ink)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var useButton: some View {
        PrimaryButton(
            title: "Use this scan",
            systemImage: "arrow.right"
        ) {
            viewModel.pause()
            onUseVideo(viewModel.video)
        }
    }
}
