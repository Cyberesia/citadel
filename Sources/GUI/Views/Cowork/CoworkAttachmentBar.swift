import SwiftUI

struct CoworkAttachmentBar: View {
    let paths: [String]
    let onRemove: (String) -> Void

    var body: some View {
        if paths.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.ps(10))
                            Text((path as NSString).lastPathComponent)
                                .font(.ps(10))
                                .lineLimit(1)
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
                    }
                }
            }
        }
    }
}
