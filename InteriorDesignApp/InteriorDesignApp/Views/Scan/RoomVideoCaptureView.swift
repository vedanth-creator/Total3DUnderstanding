import PhotosUI
import SwiftUI

struct RoomVideoCaptureView: View {
    @ObservedObject var viewModel: RoomVideoCaptureViewModel
    let onCancel: () -> Void
    let onVideoReady: (RoomScanVideo) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var simulatorVideoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if viewModel.isSimulatorTestMode {
                simulatorFallback
            } else {
                CameraPreviewView(session: viewModel.captureService.captureSession)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(viewModel.state == .preparing ? 0.45 : 0))
            }

            VStack(spacing: 16) {
                recorderHeader
                Spacer()

                if viewModel.isRecording {
                    ScanGuidanceOverlay(
                        guidance: viewModel.guidance,
                        progress: viewModel.mockedCoverageProgress,
                        warning: viewModel.guidanceWarning
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let statusMessage {
                    Text(statusMessage)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                recorderControls
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: viewModel.state)
        .task {
            await viewModel.prepare(onVideoReady: onVideoReady)
        }
        .onDisappear {
            viewModel.stopSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                viewModel.handleBackgrounding()
            } else if phase == .active {
                Task { await viewModel.resumeAfterBackgrounding() }
            }
        }
        .onChange(of: simulatorVideoItem) { _, item in
            guard let item else { return }
            Task {
                await viewModel.importSimulatorVideo(from: item)
                simulatorVideoItem = nil
            }
        }
        .alert(
            "Camera unavailable",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Finish this scan?",
            isPresented: $viewModel.isLowCoverageConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Finish Anyway", action: viewModel.finishLowCoverageRecording)
            Button("Continue Scanning", role: .cancel, action: viewModel.continueScanning)
        } message: {
            Text("This scan may not capture the entire room and could reduce reconstruction quality. Room coverage is currently a mocked estimate, not a geometric measurement.")
        }
    }

    private var recorderHeader: some View {
        HStack {
            Button {
                if viewModel.isRecording {
                    viewModel.cancelRecording()
                }
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel(viewModel.isRecording ? "Cancel recording" : "Close camera")

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(viewModel.elapsedTimeText)
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .accessibilityLabel("Elapsed time \(viewModel.elapsedTimeText)")
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var recorderControls: some View {
        if viewModel.isSimulatorTestMode {
            PhotosPicker(selection: $simulatorVideoItem, matching: .videos) {
                Label("Choose test video", systemImage: "video.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(AppTheme.ink)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityHint("Uses an existing video instead of a simulator camera")
        } else if viewModel.isRecording {
            Button(action: viewModel.requestStopRecording) {
                ZStack {
                    Circle().fill(.white).frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 28, height: 28)
                }
            }
            .accessibilityLabel("Stop recording")
        } else if viewModel.state == .ready {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 82, height: 82)
                    Circle().fill(.red).frame(width: 66, height: 66)
                }
            }
            .accessibilityLabel("Start room scan recording")
        } else if viewModel.state == .preparing || viewModel.state == .finishing {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .accessibilityLabel(viewModel.state == .preparing ? "Preparing camera" : "Saving video")
        } else if case .unavailable = viewModel.state {
            Button("Open Camera Settings", action: openApplicationSettings)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(AppTheme.ink)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var simulatorFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "28302A")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 48, weight: .light))
                Text("Simulator Test Input")
                    .font(.title2.bold())
                Text("The Simulator does not provide a production room-scan camera. Choose an existing video to test the workflow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .foregroundStyle(.white)
        }
    }

    private var statusMessage: String? {
        switch viewModel.state {
        case let .unavailable(message), let .interrupted(message):
            message
        case .ready:
            "Start at one corner and return toward this view before finishing."
        default:
            nil
        }
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
