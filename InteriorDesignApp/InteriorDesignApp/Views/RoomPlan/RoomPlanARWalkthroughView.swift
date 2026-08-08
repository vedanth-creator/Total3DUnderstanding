import ARKit
import RealityKit
import SwiftUI

struct RoomPlanARWalkthroughView: View {
    @ObservedObject var viewModel: EditableRoomPlanViewModel
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            RoomPlanARView(viewModel: viewModel)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                CircleIconButton(systemImage: "chevron.left", action: onBack)
                VStack(alignment: .leading, spacing: 2) {
                    Text("View Changes in AR")
                        .font(.headline)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
        .onAppear { AppDebugLog.write("RoomPlan AR walkthrough appeared") }
        .onDisappear { AppDebugLog.write("RoomPlan AR walkthrough disappeared") }
    }

    private var statusMessage: String {
        if viewModel.worldMap == nil { return "Coordinate map unavailable" }
        if viewModel.arChangeCount == 0 { return "No layout changes to preview" }
        return "\(viewModel.arChangeCount) change\(viewModel.arChangeCount == 1 ? "" : "s") · move slowly to relocalize"
    }
}

private struct RoomPlanARView: UIViewRepresentable {
    @ObservedObject var viewModel: EditableRoomPlanViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )
        view.scene.addAnchor(context.coordinator.sceneCoordinator.anchor)
        context.coordinator.sceneCoordinator.synchronize(
            project: viewModel.project
        )

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = viewModel.worldMap
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        AppDebugLog.write(
            "RoomPlan AR session started; initialWorldMap=\(viewModel.worldMap != nil)"
        )
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.sceneCoordinator.synchronize(
            project: viewModel.project
        )
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        view.session.pause()
        AppDebugLog.write("RoomPlan AR session paused")
    }

    @MainActor
    final class Coordinator {
        let sceneCoordinator = RoomPlanARSceneCoordinator()
    }
}
