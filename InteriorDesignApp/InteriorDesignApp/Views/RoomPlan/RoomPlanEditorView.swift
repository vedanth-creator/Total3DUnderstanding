import SwiftUI

struct RoomPlanEditorView: View {
    @ObservedObject var viewModel: EditableRoomPlanViewModel
    let onBack: () -> Void
    let onViewInAR: () -> Void

    @State private var exportItem: RoomPlanExportItem?
    @State private var isAddSheetPresented = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack(alignment: .bottom) {
                RoomPlanTopDownView(viewModel: viewModel)

                VStack {
                    HStack {
                        Spacer()
                        cameraControls
                    }
                    Spacer()

                    if let selected = viewModel.selectedObject {
                        Label(selected.category, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(AppTheme.ink)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    editingControls
                    PrimaryButton(
                        title: "View Changes in AR",
                        systemImage: "arkit",
                        action: onViewInAR
                    )
                }
                .padding(16)
            }
        }
        .background(AppTheme.background)
        .sheet(isPresented: $isAddSheetPresented) {
            RoomPlanAddObjectSheet { category in
                viewModel.add(category)
                isAddSheetPresented = false
            }
            .presentationDetents([.medium])
        }
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
                Text("3D layout editor")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()

            Button { viewModel.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            exportAndDebugMenu
        }
        .padding(16)
    }

    private var exportAndDebugMenu: some View {
        Menu {
            Button("Room information", systemImage: "info.circle") {
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

    private var cameraControls: some View {
        HStack(spacing: 4) {
            cameraButton("Top", systemImage: "square.grid.2x2") {
                viewModel.setCameraPreset(.top)
            }
            cameraButton("3D", systemImage: "cube.transparent") {
                viewModel.setCameraPreset(.perspective)
            }
            cameraButton("Reset", systemImage: "viewfinder") {
                viewModel.resetCamera()
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cameraButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var editingControls: some View {
        HStack(spacing: 8) {
            controlButton("Add", systemImage: "plus", enabled: true) {
                isAddSheetPresented = true
            }
            controlButton("Rotate", systemImage: "rotate.right", enabled: viewModel.canDelete) {
                viewModel.rotateSelected(by: .pi / 12)
            }
            controlButton(
                "Delete",
                systemImage: "trash",
                enabled: viewModel.canDelete,
                role: .destructive
            ) {
                viewModel.deleteSelected()
            }
            controlButton("Reset Layout", systemImage: "arrow.counterclockwise", enabled: true) {
                viewModel.resetLayout()
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
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct RoomPlanAddObjectSheet: View {
    let onSelect: (RoomPlanAddCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(RoomPlanAddCategory.allCases) { category in
                        Button {
                            onSelect(category)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: category.systemImage)
                                    .font(.title2)
                                Text(category.rawValue)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .foregroundStyle(AppTheme.ink)
                            .background(Color.white.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.line)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Add to room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct RoomPlanExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
