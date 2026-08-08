import SwiftUI

struct RoomPlanCaptureView: View {
    @ObservedObject var viewModel: RoomPlanCaptureViewModel
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .scanning, .processing:
                RoomPlanCaptureContainer(viewModel: viewModel)
                    .ignoresSafeArea()
            case .preparing:
                statusView(
                    icon: "camera.viewfinder",
                    title: "Preparing RoomPlan",
                    message: "Checking camera and LiDAR availability."
                )
            case .unsupported:
                statusView(
                    icon: "iphone.slash",
                    title: "RoomPlan isn’t supported",
                    message: "Use a LiDAR-equipped iPhone or iPad to try this experimental scan."
                )
            case .permissionDenied:
                statusView(
                    icon: "camera.fill",
                    title: "Camera access is off",
                    message: "Allow camera access in Settings to scan a room with RoomPlan."
                )
            case .failed(let message):
                statusView(
                    icon: "exclamationmark.triangle",
                    title: "Scan couldn’t finish",
                    message: message
                )
            }

            if viewModel.state == .scanning || viewModel.state == .processing {
                controls
            }
        }
        .background(Color.black)
        .task {
            if viewModel.state == .preparing {
                await viewModel.prepare()
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    viewModel.cancel()
                    onCancel()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.64))

                Spacer()

                Button("Finish") {
                    viewModel.finish()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(!viewModel.isFinishEnabled)
            }
            .padding()

            Spacer()

            if viewModel.state == .processing {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Building structured room…")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(.bottom, 28)
            }
        }
    }

    private func statusView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .medium))
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Back", action: onCancel)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ink)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }
}
