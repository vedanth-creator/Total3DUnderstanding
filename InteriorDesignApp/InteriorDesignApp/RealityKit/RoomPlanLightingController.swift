import RealityKit

@MainActor
enum RoomPlanLightingController {
    static func makeEditorLighting(roomHeight: Float) -> Entity {
        let root = Entity()
        root.name = "roomplan-editor-lighting"

        let key = DirectionalLight()
        key.name = "roomplan-soft-key"
        key.light.intensity = 1_250
        key.light.color = .init(red: 1, green: 0.96, blue: 0.90, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 9,
            depthBias: 1.4
        )
        key.look(
            at: SIMD3<Float>(0, max(roomHeight * 0.35, 0.8), 0),
            from: SIMD3<Float>(-4.5, max(roomHeight + 3, 5.5), 4),
            relativeTo: nil
        )
        root.addChild(key)

        let fill = PointLight()
        fill.name = "roomplan-soft-fill"
        fill.light.intensity = 520
        fill.light.color = .init(red: 0.88, green: 0.93, blue: 1, alpha: 1)
        fill.light.attenuationRadius = 11
        fill.position = SIMD3<Float>(2.5, max(roomHeight * 0.78, 2), 2.5)
        root.addChild(fill)

        let ambientFill = PointLight()
        ambientFill.name = "roomplan-ambient-fill"
        ambientFill.light.intensity = 260
        ambientFill.light.attenuationRadius = 14
        ambientFill.position = SIMD3<Float>(-2.2, max(roomHeight * 0.55, 1.6), -2)
        root.addChild(ambientFill)

        return root
    }
}
