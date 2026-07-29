import CoreGraphics
import RealityKit
import simd

@MainActor
final class CameraController {
    let cameraEntity = Entity()
    let orbitTargetEntity = Entity()

    private(set) var target = SIMD3<Float>(0, 1.0, 0)
    private(set) var yaw: Float = 0.48
    private(set) var pitch: Float = 0.42
    private(set) var distance: Float = 8.0

    private var defaultDistance: Float = 8.0
    var cameraDidChange: (() -> Void)?

    private let minimumPitch: Float = 0.12
    private let maximumPitch: Float = 1.18
    private let minimumDistance: Float = 3.0
    private let maximumDistance: Float = 15.0

    init() {
        cameraEntity.name = "room-camera"
        orbitTargetEntity.name = "room-camera-orbit-target"
        cameraEntity.components.set(
            PerspectiveCameraComponent(
                near: 0.05,
                far: 50,
                fieldOfViewInDegrees: 50
            )
        )
    }

    func configure(for scene: RoomScene, reset: Bool) {
        let largestRoomDimension = Float(max(scene.roomWidth, scene.roomDepth))
        defaultDistance = min(
            max(largestRoomDimension * 1.55, 5.5),
            12.0
        )
        if reset {
            resetView()
        } else {
            applyCameraTransform()
        }
    }

    func resetView() {
        target = SIMD3<Float>(0, 1.05, 0)
        yaw = 0.48
        pitch = 0.42
        distance = defaultDistance
        applyCameraTransform()
    }

    func orbit(deltaX: CGFloat, deltaY: CGFloat) {
        yaw -= Float(deltaX) * 0.008
        pitch = min(
            max(pitch + Float(deltaY) * 0.006, minimumPitch),
            maximumPitch
        )
        applyCameraTransform(debugGesture: "orbit")
    }

    func pan(deltaX: CGFloat, deltaY: CGFloat) {
        let sensitivity = distance * 0.0017
        let cameraRight = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        target += cameraRight * (-Float(deltaX) * sensitivity)
        target.y = min(max(target.y + Float(deltaY) * sensitivity, 0.2), 3.5)
        applyCameraTransform(debugGesture: "pan")
    }

    func zoom(scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        distance = min(
            max(distance / Float(scale), minimumDistance),
            maximumDistance
        )
        applyCameraTransform(debugGesture: "pinch")
    }

    func logCameraPositionIfChanged(from previousPosition: inout SIMD3<Float>?) {
        let position = cameraEntity.position(relativeTo: nil)
        guard previousPosition != position else { return }
        previousPosition = position
        logCameraPosition(position, gesture: "RealityView camera control")
    }

    private func applyCameraTransform(debugGesture: String? = nil) {
        let horizontalDistance = distance * cos(pitch)
        let position = SIMD3<Float>(
            target.x + horizontalDistance * sin(yaw),
            target.y + distance * sin(pitch),
            target.z + horizontalDistance * cos(yaw)
        )
        cameraEntity.look(
            at: target,
            from: position,
            upVector: SIMD3<Float>(0, 1, 0),
            relativeTo: nil
        )
        orbitTargetEntity.position = target
        if let debugGesture {
            logCameraPosition(position, gesture: debugGesture)
        }
        cameraDidChange?()
    }

    private func logCameraPosition(_ position: SIMD3<Float>, gesture: String) {
        #if DEBUG
        print(
            String(
                format: "[RoomCamera] %@ changed position to (x: %.3f, y: %.3f, z: %.3f)",
                gesture,
                position.x,
                position.y,
                position.z
            )
        )
        #endif
    }
}
