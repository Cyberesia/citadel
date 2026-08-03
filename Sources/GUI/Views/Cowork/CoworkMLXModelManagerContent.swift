import SwiftUI

/// Murmura-style MLX model manager: curated list, download, delete, pick active model.
struct CoworkMLXModelManagerContent: View {
    @EnvironmentObject var cowork: CoworkState
    @ObservedObject private var library = CoworkMLXModelLibrary.shared
    @AppStorage("cowork.selectedMLXRepoID") private var selectedMLXRepoID = CoworkMLXModelCatalog.defaultRepoID

    @State private var searchQuery = ""
    @State private var deleteConfirmRepo: String?
    var onDismiss: () -> Void = {}

    private var filteredModels: [CoworkMLXModelInfo] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return CoworkMLXModelCatalog.models }
        return CoworkMLXModelCatalog.models.filter {
            $0.id.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cowork.mlxRuntimeAvailable && cowork.mlxRuntimeInstallMessage == nil {
                mlxRuntimeBanner
            }

            Text(L10n.mlxManagerSubtitle)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)

            if let err = library.downloadError {
                Text(err)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.signalDeny)
            }

            TextField(L10n.searchModels, text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.ps(11))
                .padding(8)
                .background(PrismTheme.surfaceMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredModels) { model in
                        modelRow(model)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .onAppear {
            Task {
                await library.refreshInstalledByteSizesAsync()
                await cowork.refreshMLXModelsAsync()
            }
        }
        .alert(L10n.mlxDeleteLocalTitle, isPresented: Binding(
            get: { deleteConfirmRepo != nil },
            set: { if !$0 { deleteConfirmRepo = nil } }
        )) {
            Button(L10n.cronCancel, role: .cancel) { deleteConfirmRepo = nil }
            Button(L10n.delete, role: .destructive) {
                if let id = deleteConfirmRepo {
                    try? library.deleteCache(repoID: id)
                    if selectedMLXRepoID == id { selectedMLXRepoID = CoworkMLXModelCatalog.defaultRepoID }
                    library.refreshInstalledByteSizes()
                    cowork.refreshMLXModels()
                }
                deleteConfirmRepo = nil
            }
        } message: {
            if let id = deleteConfirmRepo {
                Text(L10n.mlxRemoveConfirm(id))
            }
        }
    }

    private func modelRow(_ model: CoworkMLXModelInfo) -> some View {
        let isInstalled = (library.installedByteSizes[model.id] ?? 0) > 0
        let isPartial = !isInstalled && (library.partialByteSizes[model.id] ?? 0) > 0
        let isBusy = library.activeDownloadRepoID == model.id
        let isSelected = selectedMLXRepoID == model.id
        let ramOK = CoworkMLXModelCatalog.physicalRAMGB() >= model.minRAMGB

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isInstalled ? "checkmark.square.fill" : "square")
                .foregroundStyle(isInstalled ? PrismTheme.accent : PrismTheme.textTertiary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    if model.supportsVision {
                        Image(systemName: "eye")
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.accentSecondary)
                    }
                }
                if let sub = model.detailSubtitle {
                    Text(sub).font(.ps(9)).foregroundStyle(PrismTheme.textSecondary)
                }
                Text("\(model.sizeLabel) · \(model.ramRequirementLabel)")
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.textTertiary)
                if !ramOK {
                    Text(L10n.mlxMoreRAM)
                        .font(.ps(9))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isInstalled else { return }
                Task {
                    let ok = await cowork.selectMLXModel(model.id)
                    if ok {
                        selectedMLXRepoID = model.id
                        onDismiss()
                    }
                }
            }

            VStack(spacing: 6) {
                if isBusy {
                    ProgressView(value: library.downloadFraction)
                        .frame(width: 72)
                    Button(L10n.cronCancel) { library.cancelDownload() }
                        .font(.ps(9))
                        .buttonStyle(PrismHandButtonStyle())
                } else if isInstalled {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PrismTheme.accent)
                    }
                    Button { deleteConfirmRepo = model.id } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(PrismTheme.signalDeny)
                    }
                    .buttonStyle(PrismHandButtonStyle())
                } else {
                    Button {
                        library.startDownload(repoID: model.id)
                    } label: {
                        Label(isPartial ? L10n.resumeDownload : L10n.download, systemImage: "arrow.down.circle")
                            .font(.ps(10, weight: .semibold))
                            .foregroundStyle(PrismTheme.accent)
                    }
                    .buttonStyle(PrismHandButtonStyle())
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrismTheme.surfaceMuted.opacity(isSelected ? 0.65 : 0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? PrismTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
    }

    private var mlxRuntimeBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = cowork.mlxRuntimeInstallMessage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message)
                        .font(.ps(10, weight: .semibold))
                        .foregroundStyle(PrismTheme.accentSecondary)
                }
            } else {
                Label(L10n.mlxFirstTimeSetup, systemImage: "arrow.down.circle")
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.accentSecondary)
                Text(L10n.mlxSetupHelp)
                    .font(.ps(9))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PrismTheme.accentSoft.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PrismTheme.accent.opacity(0.25), lineWidth: 1))
        )
    }
}
