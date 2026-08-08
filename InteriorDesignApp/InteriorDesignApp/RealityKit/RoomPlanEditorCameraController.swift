import CoreGraphics
import RealityKit

@MainActor
final class RoomPlanEditorCameraController {
    private let sceneRoot: Entity
    private var bounds = RoomPlanFloorBounds(
        minimumX: -2.5,
        maximumX: 2.5,
        minimumZ: -2.5,
        maximumZ: 2.5
    )
    private var span: Float = 5
    private var target = SIMD3<Float>(0, 0.5, 0)
    private var yaw: Float = 0.65
    private var pitch: Float = 0.75
    private var distance: Float = 7
    private(set) var preset: RoomPlanEditorCameraPreset = .perspective
    private(set) var cameraTransform = matrix_identity_float4x4

    init(sceneRoot: Entity) {
        self.sceneRoot = sceneRoot
    }

    func configure(bounds: RoomPlanFloorBounds, roomHeight: Float) {
        self.bounds = bounds
        span = max(max(bounds.width, bounds.depth), 2)
        applyPreset(preset, roomHeight: roomHeight, animated: false)
    }

    func applyPreset(
        _ preset: RoomPlanEditorCameraPreset,
        roomHeight: Float,
        animated: Bool = true
    ) {
        self.preset = preset
        switch preset {
        case .top:
            yaw = 0
            pitch = 1.48
            distance = span * 1.25
            target = bounds.center
        case .perspective:
            yaw = 0.65
            pitch = 0.72
            distance = span * 1.45
            target = bounds.center + SIMD3<Float>(0, min(roomHeight * 0.25, 0.8), 0)
        }
        applyTransform(animated: animated)
    }

    func orbit(delta: CGPoint) {
        yaw -= Float(delta.x) * 0.008
        pitch = min(max(pitch + Float(delta.y) * 0.006, 0.22), 1.48)
        applyTransform(animated: false)
    }

    func pan(delta: CGPoint) {
        let scale = distance * 0.0017
        let right = normalizedXZ(SIMD3<Float>(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        ))
        let cameraUp = SIMD3<Float>(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        )
        let floorUp = normalizedXZ(cameraUp)
        target -= right * Float(delta.x) * scale
        target += floorUp * Float(delta.y) * scale
        target.x = min(max(target.x, bounds.minimumX), bounds.maximumX)
        target.z = min(max(target.z, bounds.minimumZ), bounds.maximumZ)
        applyTransform(animated: false)
    }

    func zoom(scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        distance = min(max(distance / Float(scale), span * 0.5), span * 4.0)
        applyTransform(animated: false)
    }

    private func applyTransform(animated: Bool) {
        let horizontalDistance = distance * cos(pitch)
        let position = SIMD3<Float>(
            target.x + horizontalDistance * sin(yaw),
            target.y + distance * sin(pitch),
            target.z + horizontalDistance * cos(yaw)
        )
        cameraTransform = lookAtCameraTransform(position: position, target: target)
        let rootTransform = Transform(matrix: cameraTransform.inverse)
        if animated {
            sceneRoot.move(
                to: rootTransform,
                relativeTo: sceneRoot.parent,
                duration: 0.32,
                timingFunction: .easeInOut
            )
        } else {
            sceneRoot.transform = rootTransform
        }
    }

    private func lookAtCameraTransform(
        position: SIMD3<Float>,
        target: SIMD3<Float>
    ) -> simd_float4x4 {
        let backward = simd_normalize(position - target)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), backward))
        let up = simd_normalize(simd_cross(backward, right))
        return simd_float4x4(columns: (
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(up.x, up.y, up.z, 0),
            SIMD4<Float>(backward.x, backward.y, backward.z, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        ))
    }

    private func normalizedXZ(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let flattened = SIMD3<Float>(vector.x, 0, vector.z)
        let length = simd_length(flattened)
        return length > 0.0001 ? flattened / length : SIMD3<Float>(1, 0, 0)
    }
}
