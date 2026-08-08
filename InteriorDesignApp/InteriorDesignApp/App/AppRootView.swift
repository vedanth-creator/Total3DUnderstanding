import SwiftUI

struct AppRootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            switch viewModel.route {
            case .home:
                HomeView(
                    viewModel: viewModel.homeViewModel,
                    onStart: viewModel.showCaptureMethods,
                    onOpenSample: viewModel.openSampleScene
                )
                .transition(.appScreen)

            case .captureMethod:
                CaptureMethodView(
                    viewModel: viewModel.captureMethodViewModel,
                    onBack: viewModel.showHome,
                    onRoomPlanScan: viewModel.showRoomPlanCapture,
                    onRecordScan: viewModel.showVideoCapture,
                    onUsePhotos: viewModel.showUpload,
                    onUseSample: viewModel.openDefaultSampleScene,
                    onVideoSelected: viewModel.showVideoReview,
                    hasSavedRoomPlanProject: viewModel.hasSavedRoomPlanProject,
                    onOpenSavedRoomPlanProject: viewModel.openSavedRoomPlanProject
                )
                .transition(.appScreen)

            case .roomPlanCapture:
                if let roomPlanCaptureViewModel = viewModel.roomPlanCaptureViewModel {
                    RoomPlanCaptureView(
                        viewModel: roomPlanCaptureViewModel,
                        onCancel: viewModel.showCaptureMethods
                    )
                    .transition(.appScreen)
                }

            case .roomPlanEditor:
                if let editableRoomPlanViewModel = viewModel.editableRoomPlanViewModel {
                    RoomPlanEditorView(
                        viewModel: editableRoomPlanViewModel,
                        onBack: viewModel.showCaptureMethods,
                        onViewInAR: viewModel.showRoomPlanAR
                    )
                    .transition(.appScreen)
                }

            case .roomPlanAR:
                if let editableRoomPlanViewModel = viewModel.editableRoomPlanViewModel {
                    RoomPlanARWalkthroughView(
                        viewModel: editableRoomPlanViewModel,
                        onBack: viewModel.returnToRoomPlanEditor
                    )
                    .transition(.appScreen)
                }

            case .videoCapture:
                if let videoCaptureViewModel = viewModel.videoCaptureViewModel {
                    RoomVideoCaptureView(
                        viewModel: videoCaptureViewModel,
                        onCancel: viewModel.showCaptureMethods,
                        onVideoReady: viewModel.showVideoReview
                    )
                    .transition(.appScreen)
                }

            case .videoReview:
                if let videoReviewViewModel = viewModel.videoReviewViewModel {
                    VideoReviewView(
                        viewModel: videoReviewViewModel,
                        onRetake: viewModel.retakeVideo,
                        onUseVideo: viewModel.beginVideoProcessing
                    )
                    .transition(.appScreen)
                }

            case .upload:
                UploadView(
                    viewModel: viewModel.uploadViewModel,
                    onBack: viewModel.showCaptureMethods,
                    onContinue: viewModel.beginProcessing
                )
                .transition(.appScreen)

            case .processing:
                if let processingViewModel = viewModel.processingViewModel {
                    ProcessingView(
                        viewModel: processingViewModel,
                        onCancel: viewModel.cancelProcessing,
                        onComplete: viewModel.showViewer
                    )
                    .transition(.appScreen)
                }

            case .viewer:
                if let viewerViewModel = viewModel.viewerViewModel {
                    RoomViewerView(
                        viewModel: viewerViewModel,
                        onClose: viewModel.showHome
                    )
                    .transition(.appScreen)
                }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: viewModel.route)
    }
}

private extension AnyTransition {
    static var appScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 1.01))
        )
    }
}
