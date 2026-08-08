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
        private weak var tapGesture: UITapGestureRecognizer?
        private weak var panGesture: UIPanGestureRecognizer?
        private weak var rotationGesture: UIRotationGestureRecognizer?

        init(viewModel: EditableRoomPlanViewModel) {
            self.viewModel = viewModel
        }

        func synchronize() {
            sceneCoordinator.synchronize(
                project: viewModel.project,
                selectedObjectID: viewModel.selectedObjectID,
                angled: viewModel.isAngledView
            )
        }

        func installGestures(on view: ARView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            tap.delegate = self
            pan.delegate = self
            rotation.delegate = self
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(rotation)
            tapGesture = tap
            panGesture = pan
            rotationGesture = rotation
        }

        func removeGestures(from view: ARView) {
            [tapGesture, panGesture, rotationGesture].compactMap { $0 }.forEach(view.removeGestureRecognizer)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? ARView else { return }
            let entity = view.entity(at: recognizer.location(in: view))
            viewModel.select(sceneCoordinator.objectID(from: entity))
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view, viewModel.selectedObjectID != nil else { return }
            switch recognizer.state {
            case .began:
                viewModel.beginTransform()
            case .changed:
                let translation = recognizer.translation(in: view)
                let span = max(
                    max(
                        viewModel.project.floorBounds.width,
                        viewModel.project.floorBounds.depth
                    ),
                    2
                )
                let points = max(min(view.bounds.width, view.bounds.height), 1)
                let metersPerPoint = span / Float(points * 0.72)
                viewModel.moveSelected(
                    by: SIMD2<Float>(
                        Float(translation.x) * metersPerPoint,
                        -Float(translation.y) * metersPerPoint
                    )
                )
                recognizer.setTranslation(.zero, in: view)
            case .ended, .cancelled, .failed:
                viewModel.endTransform()
            default:
                break
            }
        }

        @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard viewModel.selectedObjectID != nil else { return }
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
            gestureRecognizer is UIRotationGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer
        }
    }
}
