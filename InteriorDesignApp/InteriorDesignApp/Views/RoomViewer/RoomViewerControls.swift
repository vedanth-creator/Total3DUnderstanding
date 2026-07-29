import UIKit

/// UIKit gesture handling for the iOS 17 `ARView` compatibility renderer.
/// Recognizers are installed directly on the active render view; installing
/// them through a SwiftUI background view can target an unrelated host wrapper.
@MainActor
final class RoomViewerControls: NSObject, UIGestureRecognizerDelegate {
    private let cameraController: CameraController
    private weak var hostView: UIView?
    private var recognizers: [UIGestureRecognizer] = []

    init(cameraController: CameraController) {
        self.cameraController = cameraController
        super.init()
    }

    func install(on hostView: UIView) {
        guard self.hostView !== hostView else { return }
        uninstall()
        self.hostView = hostView

        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1
        orbit.cancelsTouchesInView = false
        orbit.delegate = self

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = self

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = self

        recognizers = [orbit, pan, pinch]
        recognizers.forEach(hostView.addGestureRecognizer)
        AppDebugLog.write("Installed \(recognizers.count) camera gesture recognizers")
    }

    func uninstall() {
        if let hostView {
            recognizers.forEach(hostView.removeGestureRecognizer)
        }
        recognizers.removeAll()
        hostView = nil
        AppDebugLog.write("Removed camera gesture recognizers")
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleOrbit(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        cameraController.orbit(deltaX: translation.x, deltaY: translation.y)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        cameraController.pan(deltaX: translation.x, deltaY: translation.y)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let scale = recognizer.scale
        recognizer.scale = 1
        cameraController.zoom(scale: scale)
    }
}
