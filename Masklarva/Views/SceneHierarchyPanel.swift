import SwiftUI

struct SceneHierarchyPanel: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 3) {
            ForEach(viewModel.document.hierarchyItems) { item in
                SceneHierarchyRow(
                    item: item,
                    isSelected: viewModel.document.selectedID == item.id,
                    isEffectivelyLocked: viewModel.document
                        .isEffectivelyLocked(item.id),
                    isEffectivelyVisible: viewModel.document
                        .isEffectivelyVisible(item.id),
                    onSelect: { viewModel.selectObject(item.id) },
                    onToggleVisibility: {
                        viewModel.selectObject(item.id)
                        viewModel.toggleSelectionVisibility()
                    },
                    onToggleLock: {
                        viewModel.selectObject(item.id)
                        viewModel.toggleSelectionLock()
                    }
                )
            }
        }
    }
}

private struct SceneHierarchyRow: View {
    let item: SceneHierarchyItem
    let isSelected: Bool
    let isEffectivelyLocked: Bool
    let isEffectivelyVisible: Bool
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onToggleLock: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: item.object.isGroup ? "folder.fill" : item.object.kind.symbol)
                    .frame(width: 16)
                Text(item.object.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isEffectivelyLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CGFloat(item.depth) * 14)
        }
        .buttonStyle(.plain)
        .padding(7)
        .background(
            isSelected ? Color.accentColor.opacity(0.25) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .opacity(isEffectivelyVisible ? 1 : 0.45)
        .contextMenu {
            Button(
                isEffectivelyVisible ? "Ausblenden" : "Einblenden",
                action: onToggleVisibility
            )
            Button(
                item.object.isLocked ? "Entsperren" : "Sperren",
                action: onToggleLock
            )
        }
        .accessibilityValue(isEffectivelyLocked ? "Gesperrt" : "Entsperrt")
    }
}
