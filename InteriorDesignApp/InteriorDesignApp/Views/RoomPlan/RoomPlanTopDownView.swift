import RealityKit
import SwiftUI

struct RoomPlanTopDownView: UIViewRepresentable {
    @ObservedObject var viewModel: EditableRoomPlanViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.environment.background = .color(
            UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1)
        )
        view.renderOptions.insert(.disableMotionBlur)
        view.scene.addAnchor(context.coordinator.sceneCoordinator.anchor)
        context.coordinator.installGestures(on: view)
        context.coordinator.synchronize()
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.synchronize()
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.removeGestures(from: view)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var viewModel: EditableRoomPlanViewModel
        let sceneCoordinator = RoomPlanSceneCoordinator()
        private lazy var cameraController = RoomPlanEditorCameraController(
            sceneRoot: sceneCoordinator.sceneRoot
        )

        private weak var tapGesture: UITapGestureRecognizer?
        private weak var orbitOrDragGesture: UIPanGestureRecognizer?
        private weak var cameraPanGesture: UIPanGestureRecognizer?
        private weak var pinchGesture: UIPinchGestureRecognizer?
        private weak var rotationGesture: UIRotationGestureRecognizer?

        private var configuredProjectID: UUID?
        private var appliedCameraPreset: RoomPlanEditorCameraPreset?
        private var appliedCameraResetToken = -1
        private var oneFingerMode: OneFingerMode = .cameraOrbit
        private var dragOffset = SIMD2<Float>(repeating: 0)

        init(viewModel: EditableRoomPlanViewModel) {
            self.viewModel = viewModel
        }

        func synchronize() {
            sceneCoordinator.synchronize(
                project: viewModel.project,
                selectedObjectID: viewModel.selectedObjectID
            )
            if configuredProjectID != viewModel.project.id {
                configuredProjectID = viewModel.project.id
                cameraController.configure(
                    bounds: viewModel.project.floorBounds,
                    roomHeight: viewModel.project.roomHeight
                )
                appliedCameraPreset = viewModel.cameraPreset
                appliedCameraResetToken = viewModel.cameraResetToken
            }
            if appliedCameraPreset != viewModel.cameraPreset {
                appliedCameraPreset = viewModel.cameraPreset
                cameraController.applyPreset(
                    viewModel.cameraPreset,
                    roomHeight: viewModel.project.roomHeight
                )
            } else if appliedCameraResetToken != viewModel.cameraResetToken {
                appliedCameraResetToken = viewModel.cameraResetToken
                cameraController.applyPreset(
                    viewModel.cameraPreset,
                    roomHeight: viewModel.project.roomHeight
                )
            }
        }

        func installGestures(on view: ARView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

            let orbitOrDrag = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleOrbitOrObjectDrag(_:))
            )
            orbitOrDrag.minimumNumberOfTouches = 1
            orbitOrDrag.maximumNumberOfTouches = 1

            let cameraPan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleCameraPan(_:))
            )
            cameraPan.minimumNumberOfTouches = 2
            cameraPan.maximumNumberOfTouches = 2

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let rotation = UIRotationGestureRecognizer(
                target: self,
                action: #selector(handleRotation(_:))
            )

            [tap, orbitOrDrag, cameraPan, pinch, rotation].forEach {
                $0.delegate = self
                view.addGestureRecognizer($0)
            }
            tapGesture = tap
            orbitOrDragGesture = orbitOrDrag
            cameraPanGesture = cameraPan
            pinchGesture = pinch
            rotationGesture = rotation
        }

        func removeGestures(from view: ARView) {
            [tapGesture, orbitOrDragGesture, cameraPanGesture, pinchGesture, rotationGesture]
                .compactMap { $0 }
                .forEach(view.removeGestureRecognizer)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? ARView else { return }
            let entity = view.entity(at: recognizer.location(in: view))
            viewModel.select(sceneCoordinator.objectID(from: entity))
        }

        @objc private func handleOrbitOrObjectDrag(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view as? ARView else { return }
            switch recognizer.state {
            case .began:
                beginOneFingerInteraction(recognizer, in: view)
            case .changed:
                switch oneFingerMode {
                case .objectDrag(let planeY):
                    guard let point = sceneCoordinator.roomPoint(
                        for: recognizer.location(in: view),
                        in: view,
                        horizontalPlaneY: planeY
                    ) else { return }
                    viewModel.moveSelected(
                        toFloorPosition: SIMD2<Float>(
                            point.x + dragOffset.x,
                            point.z + dragOffset.y
                        )
                    )
                case .cameraOrbit:
                    let delta = recognizer.translation(in: view)
                    cameraController.orbit(delta: delta)
                    recognizer.setTranslation(.zero, in: view)
                }
            case .ended, .cancelled, .failed:
                if case .objectDrag = oneFingerMode {
                    viewModel.endTransform()
                }
                oneFingerMode = .cameraOrbit
            default:
                break
            }
        }

        private func beginOneFingerInteraction(
            _ recognizer: UIPanGestureRecognizer,
            in view: ARView
        ) {
            let location = recognizer.location(in: view)
            let touchedID = sceneCoordinator.objectID(from: view.entity(at: location))
            guard
                let selected = viewModel.selectedObject,
                touchedID == selected.id,
                let floorPoint = sceneCoordinator.roomPoint(
                    for: location,
                    in: view,
                    horizontalPlaneY: selected.transform.position.y
                )
            else {
                oneFingerMode = .cameraOrbit
                return
            }
            let position = selected.transform.position
            dragOffset = SIMD2<Float>(position.x - floorPoint.x, position.z - floorPoint.z)
            oneFingerMode = .objectDrag(planeY: position.y)
            viewModel.beginTransform()
        }

        @objc private func handleCameraPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            if recognizer.state == .changed {
                cameraController.pan(delta: recognizer.translation(in: view))
                recognizer.setTranslation(.zero, in: view)
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            if recognizer.state == .changed {
                cameraController.zoom(scale: recognizer.scale)
                recognizer.scale = 1
            }
        }

        @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard viewModel.selectedObject != nil else { return }
            switch recognizer.state {
            case .began:
                viewModel.beginTransform()
            case .changed:
                viewModel.rotateSelected(by: Float(-recognizer.rotation), recordsUndo: false)
                recognizer.rotation = 0
            case .ended, .cancelled, .failed:
                viewModel.endTransform()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let multiTouchTypes: [AnyClass] = [
                UIPinchGestureRecognizer.self,
                UIRotationGestureRecognizer.self
            ]
            return multiTouchTypes.contains { gestureRecognizer.isKind(of: $0) }
                || multiTouchTypes.contains { otherGestureRecognizer.isKind(of: $0) }
        }
    }
}

private enum OneFingerMode {
    case cameraOrbit
    case objectDrag(planeY: Float)
}
