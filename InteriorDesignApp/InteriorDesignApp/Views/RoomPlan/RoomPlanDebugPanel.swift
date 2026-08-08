import SwiftUI
import simd

struct RoomPlanDebugPanel: View {
    @ObservedObject var viewModel: EditableRoomPlanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Room") {
                    value("Walls", viewModel.project.walls.count)
                    value("Doors", viewModel.project.doors.count)
                    value("Windows", viewModel.project.windows.count)
                    value("Openings", viewModel.project.openings.count)
                    value("Captured objects", viewModel.project.originalObjects.count)
                    value("Active objects", viewModel.project.objects.filter { !$0.isRemoved }.count)
                    value("AR changes", viewModel.arChangeCount)
                    value(
                        "Dimensions",
                        String(
                            format: "%.2f × %.2f × %.2f m",
                            viewModel.project.floorBounds.width,
                            viewModel.project.roomHeight,
                            viewModel.project.floorBounds.depth
                        )
                    )
                }

                if let object = viewModel.selectedObject {
                    Section("Selected object") {
                        value("Category", object.category)
                        value("Source", object.source.rawValue.capitalized)
                        value(
                            "Dimensions",
                            String(
                                format: "%.2f × %.2f × %.2f m",
                                object.dimensions.width,
                                object.dimensions.height,
                                object.dimensions.depth
                            )
                        )
                        let position = object.transform.position
                        value(
                            "Position",
                            String(format: "x %.2f, y %.2f, z %.2f", position.x, position.y, position.z)
                        )
                        value("Transform", transformDescription(object.transform.matrix))
                    }
                }
            }
            .navigationTitle("RoomPlan Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func value(_ label: String, _ value: some CustomStringConvertible) -> some View {
        LabeledContent(label, value: value.description)
    }

    private func transformDescription(_ transform: simd_float4x4) -> String {
        (0..<4).map { row in
            String(
                format: "[%.2f %.2f %.2f %.2f]",
                transform[row, 0], transform[row, 1], transform[row, 2], transform[row, 3]
            )
        }.joined(separator: "\n")
    }
}
