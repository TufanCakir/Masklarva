import SwiftUI

struct MeshSelectionControls: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Mesh-Auswahl",
                selection: Binding(
                    get: { viewModel.meshSelectionMode },
                    set: { viewModel.setMeshSelectionMode($0) }
                )
            ) {
                ForEach(MeshSelectionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.meshSelectionMode == .face {
                DisclosureGroup("Flächen bearbeiten") {
                    FaceExtrusionControls(
                        isEnabled: viewModel.canSeparateMeshSelection,
                        action: viewModel.extrudeSelectedMeshFaces
                    )
                    Divider()
                    FaceInsetControls(
                        isEnabled: viewModel.canSeparateMeshSelection,
                        action: viewModel.insetSelectedMeshFaces
                    )
                }
            }

            if viewModel.meshSelectionMode == .edge {
                DisclosureGroup("Kanten bearbeiten") {
                    EdgeBevelControls(
                        isEnabled: viewModel.canBevelSelectedEdge,
                        action: viewModel.bevelSelectedMeshEdge
                    )
                }
            }

            if viewModel.meshSelectionMode == .vertex {
                DisclosureGroup("Punkte bearbeiten") {
                    Button("Zur Mitte verschweißen", systemImage: "arrow.triangle.merge") {
                        viewModel.weldSelectedMeshVertices()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canWeldSelectedVertices)
                }
            }

            DisclosureGroup("Duplizieren & bewegen") {
                DuplicateMoveControls(
                    isEnabled: viewModel.canDuplicateMeshSelection,
                    action: viewModel.duplicateSelectedMeshGeometry
                )
            }

            DisclosureGroup("Subdivision") {
                SubdivisionControls(
                    isEnabled: viewModel.canSubdivideSelectedMesh,
                    linearAction: viewModel.linearSubdivideSelectedMesh,
                    smoothAction: viewModel.catmullClarkSubdivideSelectedMesh
                )
            }

            Menu {
                Button("Alles auswählen", systemImage: "checkmark.circle") {
                    viewModel.selectAllMeshElements()
                }
                Button("Auswahl umkehren", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                    viewModel.invertMeshSelection()
                }
                Button("Auswahl aufheben", systemImage: "xmark.circle") {
                    viewModel.deselectAllMeshElements()
                }
                Divider()
                Button("Geometrie duplizieren", systemImage: "plus.square.on.square") {
                    viewModel.duplicateSelectedMeshGeometry()
                }
                .disabled(!viewModel.canDuplicateMeshSelection)
                Button("Mesh prüfen", systemImage: "checkmark.shield") {
                    viewModel.validateSelectedMesh()
                }
                .disabled(!viewModel.canValidateSelectedMesh)
                Button("Normalen neu berechnen", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.recalculateSelectedMeshNormals()
                }
                Button("Normalen umkehren", systemImage: "arrow.up.and.down") {
                    viewModel.flipSelectedMeshFaceNormals()
                }
                .disabled(!viewModel.canSeparateMeshSelection)
                Button("Auswahl separieren", systemImage: "square.on.square") {
                    viewModel.separateSelectedMeshFaces()
                }
                .disabled(!viewModel.canSeparateMeshSelection)
                Button("Ausgewählte Geometrie löschen", systemImage: "trash", role: .destructive) {
                    viewModel.deleteSelectedMeshGeometry()
                }
                .disabled(viewModel.meshSelectionCount == 0)
            } label: {
                Label(
                    "\(viewModel.meshSelectionCount) ausgewählt",
                    systemImage: "selection.pin.in.out"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .sheet(item: $viewModel.meshValidationReport) { report in
            MeshValidationReportView(
                report: report,
                dismiss: { viewModel.meshValidationReport = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct FaceExtrusionControls: View {
    let isEnabled: Bool
    let action: (Float) -> Void
    @State private var distance: Float = 0.15

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Extrusion")
                    .font(.caption)
                Spacer()
                Text(distance, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $distance, in: -1...1, step: 0.05) {
                Text("Extrusionsdistanz")
            }
            Button("Extrudieren", systemImage: "square.3.layers.3d") {
                action(distance)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!isEnabled || abs(distance) < 0.001)
        }
    }
}

private struct FaceInsetControls: View {
    let isEnabled: Bool
    let action: (Float) -> Void
    @State private var amount: Float = 0.2

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Inset")
                    .font(.caption)
                Spacer()
                Text(amount, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $amount, in: 0.05...0.9, step: 0.05) {
                Text("Inset-Stärke")
            }
            Button("Inset anwenden", systemImage: "square.dashed") {
                action(amount)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(!isEnabled)
        }
    }
}

private struct EdgeBevelControls: View {
    let isEnabled: Bool
    let action: (Float) -> Void
    @State private var width: Float = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Breite")
                    .font(.caption)
                Spacer()
                Text(width, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $width, in: 0.01...0.4, step: 0.01) {
                Text("Bevel-Breite")
            }
            Button("Kante beveln", systemImage: "square.stack.3d.up") {
                action(width)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!isEnabled)
        }
    }
}

private struct DuplicateMoveControls: View {
    let isEnabled: Bool
    let action: (SIMD3<Float>) -> Void
    @State private var axis: MeshOffsetAxis = .x
    @State private var distance: Float = 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Achse", selection: $axis) {
                ForEach(MeshOffsetAxis.allCases) { axis in
                    Text(axis.rawValue.uppercased())
                        .tag(axis)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Distanz")
                    .font(.caption)
                Spacer()
                Text(distance, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $distance, in: -2...2, step: 0.1) {
                Text("Verschiebungsdistanz")
            }
            Button("Duplizieren und bewegen", systemImage: "arrow.up.right.square") {
                action(axis.offset(distance: distance))
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(!isEnabled || abs(distance) < 0.001)
        }
    }
}

private enum MeshOffsetAxis: String, CaseIterable, Identifiable {
    case x, y, z

    var id: Self { self }

    func offset(distance: Float) -> SIMD3<Float> {
        switch self {
        case .x: [distance, 0, 0]
        case .y: [0, distance, 0]
        case .z: [0, 0, distance]
        }
    }
}

private struct SubdivisionControls: View {
    let isEnabled: Bool
    let linearAction: () -> Void
    let smoothAction: (Float) -> Void
    @State private var smoothingStrength: Float = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Linear unterteilen", systemImage: "square.grid.2x2") {
                linearAction()
            }
            .buttonStyle(.bordered)
            .disabled(!isEnabled)

            HStack {
                Text("Glättung")
                    .font(.caption)
                Spacer()
                Text(
                    smoothingStrength,
                    format: .percent.precision(.fractionLength(0))
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Slider(value: $smoothingStrength, in: 0...1, step: 0.05) {
                Text("Catmull-Clark-Glättung")
            }
            Button("Glätten und unterteilen", systemImage: "circle.grid.2x2") {
                smoothAction(smoothingStrength)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        }
    }
}
