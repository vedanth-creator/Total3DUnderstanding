import RealityKit
import SwiftUI

struct RealityRoomView: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    let resetViewToken: Int
    let onFurnitureSelection: () -> Void

    @StateObject private var sceneCoordinator = RoomSceneCoordinator()

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                ModernRealityRoomView(
                    viewModel: viewModel,
                    sceneCoordinator: sceneCoordinator,
                    onFurnitureSelection: onFurnitureSelection
                )
            } else {
                LegacyRealityRoomView(
                    scene: viewModel.scene,
                    selectedFurnitureID: viewModel.selectedFurnitureID,
                    sceneCoordinator: sceneCoordinator,
                    onSelect: handleSelection
                )
            }
        }
        .onChange(of: resetViewToken) { _, _ in
            sceneCoordinator.resetCamera()
        }
        .frame(minHeight: 460)
        .background(
            LinearGradient(
                colors: [Color(hex: "EEECE7"), Color(hex: "DCD8CF")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }

    private func handleSelection(_ furnitureID: UUID?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            viewModel.select(furnitureID: furnitureID)
            if furnitureID != nil {
                onFurnitureSelection()
            }
        }
    }
}

@available(iOS 18.0, *)
private struct ModernRealityRoomView: View {
    @ObservedObject var viewModel: RoomViewerViewModel
    let sceneCoordinator: RoomSceneCoordinator
    let onFurnitureSelection: () -> Void

    var body: some View {
        RealityView { content in
            // Add the virtual camera first, then apply its room-aware default
            // transform while it is attached. RealityKit observes that initial
            // transform before presenting the first frame.
            content.camera = .virtual
            content.add(sceneCoordinator.cameraController.cameraEntity)
            AppDebugLog.write("Camera entity attached to iOS 18+ RealityView")
            content.add(sceneCoordinator.cameraController.orbitTargetEntity)
            AppDebugLog.write("Orbit target attached to iOS 18+ RealityView")
            content.add(sceneCoordinator.rootEntity)
            AppDebugLog.write("Room/content root attached to iOS 18+ RealityView")
            content.cameraTarget = sceneCoordinator.cameraController.orbitTargetEntity
            let isNewScene = sceneCoordinator.synchronize(
                scene: viewModel.scene,
                selectedFurnitureID: viewModel.selectedFurnitureID
            )
            if isNewScene {
                sceneCoordinator.requestInitialCameraReset(
                    for: viewModel.scene.id,
                    renderer: .realityView
                )
            }
            AppDebugLog.write("RealityView scene creation completed")
        } update: { content in
            let isNewScene = sceneCoordinator.synchronize(
                scene: viewModel.scene,
                selectedFurnitureID: viewModel.selectedFurnitureID
            )
            content.cameraTarget = sceneCoordinator.cameraController.orbitTargetEntity
            if isNewScene {
                sceneCoordinator.requestInitialCameraReset(
                    for: viewModel.scene.id,
                    renderer: .realityView
                )
            }
        }
        // Let RealityView own camera input on iOS 18+. This is the supported
        // path for the virtual camera and avoids bridging recognizers through
        // SwiftUI's private hosting hierarchy.
        .realityViewCameraControls(.orbit)
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let furnitureID = sceneCoordinator.furnitureID(for: value.entity)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        viewModel.select(furnitureID: furnitureID)
                        if furnitureID != nil {
                            onFurnitureSelection()
                        }
                    }
                }
        )
    }
}

private struct LegacyRealityRoomView: UIViewRepresentable {
    let scene: RoomScene
    let selectedFurnitureID: UUID?
    let sceneCoordinator: RoomSceneCoordinator
    let onSelect: (UUID?) -> Void

    func makeCoordinator() -> InteractionCoordinator {
        InteractionCoordinator(sceneCoordinator: sceneCoordinator, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.environment.background = .color(UIColor(red: 0.88, green: 0.86, blue: 0.82, alpha: 1))
        arView.renderOptions.insert(.disableMotionBlur)
        sceneCoordinator.attachFallback(to: arView)
        let isNewScene = sceneCoordinator.synchronize(
            scene: scene,
            selectedFurnitureID: selectedFurnitureID
        )
        if isNewScene {
            sceneCoordinator.requestInitialCameraReset(
                for: scene.id,
                renderer: .arViewCompatibility
            )
        }

        context.coordinator.installTapRecognizer(on: arView)
        context.coordinator.cameraGestures.install(on: arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.onSelect = onSelect
        let isNewScene = sceneCoordinator.synchronize(
            scene: scene,
            selectedFurnitureID: selectedFurnitureID
        )
        if isNewScene {
            sceneCoordinator.requestInitialCameraReset(
                for: scene.id,
                renderer: .arViewCompatibility
            )
        }
    }

    static func dismantleUIView(_ arView: ARView, coordinator: InteractionCoordinator) {
        coordinator.removeTapRecognizer(from: arView)
        coordinator.cameraGestures.uninstall()
    }

    @MainActor
    final class InteractionCoordinator: NSObject {
        let sceneCoordinator: RoomSceneCoordinator
        let cameraGestures: RoomViewerControls
        var onSelect: (UUID?) -> Void
        private weak var tapRecognizer: UITapGestureRecognizer?

        init(
            sceneCoordinator: RoomSceneCoordinator,
            onSelect: @escaping (UUID?) -> Void
        ) {
            self.sceneCoordinator = sceneCoordinator
            self.cameraGestures = RoomViewerControls(
                cameraController: sceneCoordinator.cameraController
            )
            self.onSelect = onSelect
        }

        func installTapRecognizer(on arView: ARView) {
            guard tapRecognizer == nil else { return }
            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(handleTap(_:))
            )
            tap.cancelsTouchesInView = false
            arView.addGestureRecognizer(tap)
            tapRecognizer = tap
            AppDebugLog.write("Installed furniture tap recognizer")
        }

        func removeTapRecognizer(from arView: ARView) {
            guard let tapRecognizer else { return }
            arView.removeGestureRecognizer(tapRecognizer)
            self.tapRecognizer = nil
            AppDebugLog.write("Removed furniture tap recognizer")
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView else { return }
            let location = recognizer.location(in: arView)
            let entity = arView.entity(at: location)
            if let entity {
                onSelect(sceneCoordinator.furnitureID(for: entity))
            } else {
                onSelect(nil)
            }
        }
    }
}
