import SwiftUI

struct CoworkAttachmentBar: View {
    let paths: [String]
    let indexedPaths: Set<String>
    let onRemove: (String) -> Void
    var onPreview: ((String) -> Void)?

    var body: some View {
        if paths.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        attachmentChip(path)
                    }
                }
            }
        }
    }

    private func attachmentChip(_ path: String) -> some View {
        let indexed = indexedPaths.contains(path)
        return HStack(spacing: 6) {
            Image(systemName: indexed ? "doc.text.fill" : "doc.fill")
                .font(.ps(10))
                .foregroundStyle(indexed ? PrismTheme.accentSecondary : PrismTheme.textSecondary)
            Text((path as NSString).lastPathComponent)
                .font(.ps(10))
                .lineLimit(1)
            if indexed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.accentSecondary)
            }
            Button {
                onRemove(path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.ps(10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PrismTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PrismTheme.surfaceMuted.opacity(0.55))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            onPreview?(path)
        }
        .help(indexed ? L10n.attachmentIndexed : L10n.previewAttachment)
    }
}
