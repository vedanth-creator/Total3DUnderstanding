import SwiftUI

struct RoomPlanEditorView: View {
    @ObservedObject var viewModel: EditableRoomPlanViewModel
    let onBack: () -> Void
    let onViewInAR: () -> Void

    @State private var exportItem: RoomPlanExportItem?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack(alignment: .bottom) {
                RoomPlanTopDownView(viewModel: viewModel)

                VStack(spacing: 12) {
                    if let selected = viewModel.selectedObject {
                        Text(selected.category)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    editingControls
                    PrimaryButton(title: "View in AR", systemImage: "arkit", action: onViewInAR)
                }
                .padding(16)
            }
        }
        .background(AppTheme.background)
        .sheet(isPresented: $viewModel.isDebugPanelPresented) {
            RoomPlanDebugPanel(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $exportItem) { item in
            VStack(spacing: 22) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 42))
                Text("Room export ready")
                    .font(.title2.bold())
                ShareLink(item: item.url) {
                    Label("Share USDZ", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ink)
            }
            .padding(28)
            .presentationDetents([.height(260)])
        }
        .alert(
            "RoomPlan",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemImage: "chevron.left", action: onBack)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.project.title)
                    .font(.headline)
                Text("RoomPlan prototype")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()

            Button {
                viewModel.isAngledView.toggle()
            } label: {
                Image(systemName: viewModel.isAngledView ? "square.3.layers.3d" : "square.grid.2x2")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Debug information") {
                    viewModel.isDebugPanelPresented = true
                }
                Button("Export original USDZ") {
                    if let url = viewModel.exportOriginal() {
                        exportItem = RoomPlanExportItem(url: url)
                    }
                }
                Button("Export edited USDZ") {
                    Task {
                        if let url = await viewModel.exportEdited() {
                            exportItem = RoomPlanExportItem(url: url)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private var editingControls: some View {
        HStack(spacing: 10) {
            controlButton("Undo", systemImage: "arrow.uturn.backward", enabled: viewModel.canUndo) {
                viewModel.undo()
            }
            controlButton("Reset", systemImage: "arrow.counterclockwise", enabled: true) {
                viewModel.reset()
            }
            controlButton("Rotate", systemImage: "rotate.right", enabled: viewModel.canDelete) {
                viewModel.rotateSelected(by: .pi / 12)
            }
            controlButton("Delete", systemImage: "trash", enabled: viewModel.canDelete, role: .destructive) {
                viewModel.deleteSelected()
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        enabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct RoomPlanExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
