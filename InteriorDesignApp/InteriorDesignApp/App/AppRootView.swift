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
                    onStart: viewModel.showUpload,
                    onOpenSample: viewModel.openSampleScene
                )
                .transition(.appScreen)

            case .upload:
                UploadView(
                    viewModel: viewModel.uploadViewModel,
                    onBack: viewModel.showHome,
                    onContinue: viewModel.beginProcessing
                )
                .transition(.appScreen)

            case .processing:
                if let processingViewModel = viewModel.processingViewModel {
                    ProcessingView(
                        viewModel: processingViewModel,
                        onCancel: viewModel.showUpload,
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

