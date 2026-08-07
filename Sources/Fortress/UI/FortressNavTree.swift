import SwiftUI

struct FortressNavTree: View {
    @ObservedObject var vm: FortressViewModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.apps)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
                Spacer()
                Text("\(vm.tree.count)")
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.tree) { node in
                        FortressTreeNodeView(
                            node: node,
                            depth: 0,
                            expanded: $expanded,
                            focus: vm.focus,
                            onSelect: { vm.selectNode($0) }
                        )
                    }
                }
            }
        }
    }
}

private struct FortressTreeNodeView: View {
    let node: ProcessFamilyNode
    let depth: Int
    @Binding var expanded: Set<String>
    let focus: MonitorFocus
    let onSelect: (ProcessFamilyNode) -> Void

    private var isExpanded: Bool { expanded.contains(node.id) }
    private var isSelected: Bool { isNodeSelected(node) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !node.children.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded { expanded.remove(node.id) }
                            else { expanded.insert(node.id) }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.ps(9, weight: .bold))
                            .foregroundStyle(PrismTheme.textTertiary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .padding(.leading, CGFloat(depth) * 12 + 4)
                } else {
                    Color.clear.frame(width: 16).padding(.leading, CGFloat(depth) * 12 + 4)
                }

                ProcessFamilyRow(node: node, isSelected: isSelected, depth: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(node) }
                    .prismClickable()
            }

            if isExpanded {
                ForEach(node.children) { child in
                    FortressTreeNodeView(
                        node: child,
                        depth: depth + 1,
                        expanded: $expanded,
                        focus: focus,
                        onSelect: onSelect
                    )
                }
            }
        }
    }

    private func isNodeSelected(_ node: ProcessFamilyNode) -> Bool {
        switch focus {
        case .all:
            return false
        case .family(let id):
            return node.familyID == id && node.kind == .family
        case .role(let familyID, let role):
            if case .roleGroup(let r) = node.kind {
                return node.familyID == familyID && r == role
            }
            return false
        case .host(let familyID, let hostKey):
            return node.kind == .host && node.familyID == familyID && node.hostKey == hostKey
        case .stream(let id):
            return node.streamID == id
        }
    }
}
