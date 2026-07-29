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
            sceneCoordinator.synchronize(
                scene: viewModel.scene,
                selectedFurnitureID: viewModel.selectedFurnitureID
            )
            content.add(sceneCoordinator.rootEntity)
            content.add(sceneCoordinator.cameraController.cameraEntity)
            content.add(sceneCoordinator.cameraController.orbitTargetEntity)
            content.camera = .virtual
            content.cameraTarget = sceneCoordinator.cameraController.orbitTargetEntity
            sceneCoordinator.startCameraDebugLogging()
        } update: { content in
            sceneCoordinator.synchronize(
                scene: viewModel.scene,
                selectedFurnitureID: viewModel.selectedFurnitureID
            )
            content.cameraTarget = sceneCoordinator.cameraController.orbitTargetEntity
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
        sceneCoordinator.synchronize(
            scene: scene,
            selectedFurnitureID: selectedFurnitureID
        )

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(InteractionCoordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        arView.addGestureRecognizer(tap)
        context.coordinator.cameraGestures.install(on: arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.onSelect = onSelect
        sceneCoordinator.synchronize(
            scene: scene,
            selectedFurnitureID: selectedFurnitureID
        )
    }

    static func dismantleUIView(_ arView: ARView, coordinator: InteractionCoordinator) {
        coordinator.cameraGestures.uninstall()
    }

    @MainActor
    final class InteractionCoordinator: NSObject {
        let sceneCoordinator: RoomSceneCoordinator
        let cameraGestures: RoomViewerControls
        var onSelect: (UUID?) -> Void

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
