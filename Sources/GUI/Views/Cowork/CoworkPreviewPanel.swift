import SwiftUI
import AppKit

struct CoworkPreviewPanel: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var isEditing = false
    @State private var editDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            if let item = selectedItem {
                previewBody(item)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        .background(PrismTheme.surfaceMuted.opacity(0.2))
    }

    private var selectedItem: CoworkPreviewItem? {
        guard let id = cowork.selectedPreviewID else { return cowork.previewItems.last }
        return cowork.previewItems.first { $0.id == id } ?? cowork.previewItems.last
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.preview)
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)

            if cowork.previewItems.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(cowork.previewItems) { item in
                            Button(item.title) {
                                cowork.selectedPreviewID = item.id
                            }
                            .buttonStyle(PrismHandButtonStyle())
                            .font(.ps(10, weight: cowork.selectedPreviewID == item.id ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    cowork.selectedPreviewID == item.id
                                        ? PrismTheme.accentSoft
                                        : PrismTheme.surfaceMuted.opacity(0.4)
                                )
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(PrismTheme.textTertiary)
            Text(L10n.previewEmpty)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
    }

    @ViewBuilder
    private func previewBody(_ item: CoworkPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.ps(11, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isTextEditable(item) {
                    if isEditing {
                        Button(L10n.cronCancel) {
                            isEditing = false
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(10))
                        Button(L10n.cronSave) {
                            Task {
                                await cowork.saveFileFromPreview(item, content: editDraft)
                                isEditing = false
                            }
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(10, weight: .semibold))
                    } else {
                        Button {
                            editDraft = item.content
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.ps(11))
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .help(L10n.editFile)
                    }
                }
                if let path = item.path {
                    Button {
                        CoworkQuickLookController.shared.present(paths: [path])
                    } label: {
                        Image(systemName: "eye")
                            .font(.ps(11))
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .help(L10n.quickLook)
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.ps(11))
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .help(L10n.openInApp)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if isEditing, isTextEditable(item) {
                TextEditor(text: $editDraft)
                    .font(.ps(11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(PrismTheme.surfaceMuted.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)
            } else {
            ScrollView {
                Group {
                    switch item.contentType {
                    case .image:
                        if let b64 = item.imageBase64,
                           let data = Data(base64Encoded: b64),
                           let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.imagePreviewFailed)
                                .font(.ps(11))
                                .foregroundStyle(PrismTheme.textSecondary)
                        }
                    case .html:
                        CoworkHTMLPreview(html: item.content)
                            .frame(minHeight: 200)
                    case .pdf:
                        if let data = Data(base64Encoded: item.content) {
                            CoworkPDFPreview(data: data)
                                .frame(minHeight: 240)
                        } else {
                            Text(L10n.pdfPreviewFailed)
                                .font(.ps(11))
                                .foregroundStyle(PrismTheme.textSecondary)
                        }
                    case .diff:
                        CoworkDiffPreview(oldText: item.diffOldText ?? "", newText: item.content)
                            .frame(minHeight: 200)
                    default:
                        Text(item.content)
                            .font(.ps(11, design: item.contentType == .code ? .monospaced : .default))
                            .foregroundStyle(PrismTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            }
        }
        .onChange(of: cowork.selectedPreviewID) { _ in
            isEditing = false
        }
    }

    private func isTextEditable(_ item: CoworkPreviewItem) -> Bool {
        guard item.path != nil else { return false }
        switch item.contentType {
        case .text, .markdown, .code, .html: return true
        default: return false
        }
    }
}
