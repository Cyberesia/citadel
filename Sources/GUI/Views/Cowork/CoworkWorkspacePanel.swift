import SwiftUI
import AppKit

struct CoworkWorkspacePanel: View {
    @EnvironmentObject var cowork: CoworkState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.workspace)
                    .font(.ps(12, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button { Task { await cowork.refreshWorkspace() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.ps(11))
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            TextField(L10n.searchFiles, text: $cowork.workspaceSearchQuery)
                .textFieldStyle(.plain)
                .font(.ps(10))
                .onSubmit { Task { await cowork.refreshWorkspace() } }

            if !cowork.fileChanges.isEmpty {
                HStack {
                    Text(L10n.changes)
                        .font(.ps(9, weight: .semibold))
                        .foregroundStyle(PrismTheme.accentSecondary)
                    Spacer()
                    Button(L10n.stageAll) {
                        Task { await cowork.stageAllFileChanges() }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9))
                    Button(L10n.resetSnapshot) {
                        Task { await cowork.resetWorkspaceSnapshot() }
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9))
                }
                ForEach(cowork.fileChanges.prefix(8)) { change in
                    HStack {
                        Text("\(change.operation): \(change.displayPath)")
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Button(L10n.stageChange) {
                            Task { await cowork.stageFileChange(change) }
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(8))
                        Button(L10n.discardChanges) {
                            Task { await cowork.discardFileChange(change) }
                        }
                        .buttonStyle(PrismHandButtonStyle())
                        .font(.ps(8))
                    }
                }
            }

            Text(cowork.workspaceDisplayPath)
                .font(.ps(9))
                .foregroundStyle(PrismTheme.textTertiary)
                .lineLimit(2)
                .help(L10n.workspaceHelp)

            if cowork.workspaceRelativePath != "." {
                Button {
                    Task { await cowork.workspaceGoUp() }
                } label: {
                    Label(L10n.up, systemImage: "chevron.left")
                        .font(.ps(10, weight: .medium))
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            Text(cowork.workspaceRelativePath == "." ? L10n.files : cowork.workspaceRelativePath)
                .font(.ps(9, weight: .semibold))
                .foregroundStyle(PrismTheme.textSecondary)

            if cowork.workspaceEntries.isEmpty {
                Text(L10n.workspaceEmpty)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(cowork.workspaceEntries) { entry in
                            workspaceRow(entry)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
        .background(PrismTheme.surfaceMuted.opacity(0.25))
    }

    @ViewBuilder
    private func workspaceRow(_ entry: CoworkFSEntry) -> some View {
        if entry.isDirectory {
            Button {
                Task { await cowork.openWorkspaceEntry(entry) }
            } label: {
                rowLabel(entry)
            }
            .buttonStyle(PrismHandButtonStyle())
        } else if isPreviewable(entry) {
            Button {
                Task { await cowork.openWorkspaceEntry(entry) }
            } label: {
                rowLabel(entry)
            }
            .buttonStyle(PrismHandButtonStyle())
            .contextMenu {
                Button(L10n.quickLook) { quickLook(entry) }
                Button(L10n.reveal) { reveal(entry) }
            }
        } else {
            HStack(spacing: 8) {
                rowLabel(entry)
                Spacer()
                Menu {
                    Button(L10n.quickLook) {
                        quickLook(entry)
                    }
                    Button(L10n.rename) {
                        renameEntry(entry)
                    }
                    Button(L10n.delete, role: .destructive) {
                        Task { await cowork.deleteWorkspaceFile(path: entryPath(entry)) }
                    }
                    if let path = entryPathOptional(entry) {
                        Button(L10n.previewDiff) {
                            Task { await cowork.openDiffPreview(path: path) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.ps(10))
                }
                .menuStyle(.borderlessButton)
                Button(L10n.reveal) { reveal(entry) }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9))
            }
        }
    }

    private func entryPath(_ entry: CoworkFSEntry) -> String {
        let base = cowork.workspaceRelativePath == "." ? "" : cowork.workspaceRelativePath + "/"
        return base + entry.name
    }

    private func entryPathOptional(_ entry: CoworkFSEntry) -> String? {
        entryPath(entry)
    }

    private func renameEntry(_ entry: CoworkFSEntry) {
        let alert = NSAlert()
        alert.messageText = L10n.renameFile
        alert.informativeText = entry.name
        let field = NSTextField(string: entry.name)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.rename)
        alert.addButton(withTitle: L10n.cronCancel)
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { return }
            Task { await cowork.renameWorkspaceFile(path: entryPath(entry), newName: newName) }
        }
    }

    private func rowLabel(_ entry: CoworkFSEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.iconName)
                .foregroundStyle(entry.isDirectory ? PrismTheme.accentSecondary : PrismTheme.textTertiary)
                .frame(width: 14)
            Text(entry.name)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PrismTheme.surfaceMuted.opacity(0.35))
        )
    }

    private func isPreviewable(_ entry: CoworkFSEntry) -> Bool {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let textTypes = ["md", "markdown", "txt", "json", "swift", "py", "js", "ts", "html", "css", "sh", "yml", "yaml", "xml", "csv"]
        let imageTypes = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
        return textTypes.contains(ext) || imageTypes.contains(ext)
    }

    private func absolutePath(_ entry: CoworkFSEntry) -> String {
        let workspace = cowork.activeConversation?.workspacePath ?? cowork.workspacePath
        let relative = cowork.workspaceRelativePath == "." ? entry.name : "\(cowork.workspaceRelativePath)/\(entry.name)"
        return (workspace as NSString).appendingPathComponent(relative)
    }

    private func quickLook(_ entry: CoworkFSEntry) {
        CoworkQuickLookController.shared.present(paths: [absolutePath(entry)])
    }

    private func reveal(_ entry: CoworkFSEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: absolutePath(entry))])
    }
}
