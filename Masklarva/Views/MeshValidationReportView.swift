import SwiftUI

struct MeshValidationReportView: View {
    let report: MeshValidationReport
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Übersicht") {
                    LabeledContent("Vertices", value: report.vertexCount.formatted())
                    LabeledContent("Kanten", value: report.edgeCount.formatted())
                    LabeledContent("Flächen", value: report.faceCount.formatted())
                    LabeledContent("Dreiecke", value: report.triangleCount.formatted())
                }

                Section("Ergebnis") {
                    Label(
                        report.isValid ? "Mesh ist gültig" : "Mesh enthält Fehler",
                        systemImage: report.isValid
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.isValid ? .green : .orange)

                    if report.warningCount > 0 {
                        LabeledContent(
                            "Warnungen",
                            value: report.warningCount.formatted()
                        )
                    }
                    if report.errorCount > 0 {
                        LabeledContent(
                            "Fehler",
                            value: report.errorCount.formatted()
                        )
                    }
                }

                if !report.issues.isEmpty {
                    Section("Details") {
                        ForEach(report.issues) { issue in
                            MeshValidationIssueRow(issue: issue)
                        }
                    }
                }
            }
            .navigationTitle("Mesh-Prüfung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: dismiss)
                }
            }
        }
    }
}

private struct MeshValidationIssueRow: View {
    let issue: MeshValidationIssue

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: issue.severity == .error
                ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .orange)
        }
    }

    private var title: LocalizedStringKey {
        switch issue.kind {
        case .duplicateVertexIdentity: "Doppelte Vertex-ID"
        case .duplicateEdgeIdentity: "Doppelte Kanten-ID"
        case .duplicateFaceIdentity: "Doppelte Flächen-ID"
        case .incompleteTriangleIndices: "Unvollständige Dreiecksindizes"
        case .invalidTriangleIndex: "Ungültiger Dreiecksindex"
        case .triangleCountMismatch: "Dreiecksabgleich fehlgeschlagen"
        case .invalidFaceReference: "Ungültige Face-Referenz"
        case .degenerateFace: "Degenerierte Fläche"
        case .invalidEdge: "Ungültige Kante"
        case .duplicateEdge: "Doppelte geometrische Kante"
        case .missingTopologyEdge: "Fehlende Topologiekante"
        case .nonManifoldEdge: "Nicht-manifold Kante"
        case .orphanVertex: "Verwaister Vertex"
        }
    }
}
