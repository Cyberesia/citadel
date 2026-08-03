import SwiftUI

struct CoworkHomeView: View {
    @EnvironmentObject var cowork: CoworkState
    @AppStorage("citadel.locale") private var localeRaw = CitadelLocale.current.rawValue
    @AppStorage("citadel.keep.dismissedWelcome") private var dismissedWelcome = false

    private var needsModel: Bool { cowork.providers.isEmpty }
    private var showWelcome: Bool { !dismissedWelcome || needsModel }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if showWelcome {
                    welcomeCard
                }
                if needsModel {
                    setupCard
                } else {
                    CoworkPromptCard()
                    readyHint
                    featureHints
                }
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            cowork.startCoreIfNeeded()
            if !needsModel {
                cowork.requestComposerFocus()
            }
            Task {
                await CoworkMLXModelLibrary.shared.refreshInstalledByteSizesAsync()
                await cowork.refreshMLXModelsAsync()
                await cowork.syncLocalBackendSelection()
                await cowork.warmMLXChatModelIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(needsModel ? L10n.keepWelcomeTitle : L10n.homeGreeting)
                .font(.ps(26, weight: .bold, design: .rounded))
                .foregroundStyle(PrismTheme.textPrimary)
                .multilineTextAlignment(.center)

            if let status = cowork.statusMessage {
                Text(cowork.localizedStatus(status) ?? status)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.signalDeny)
                    .multilineTextAlignment(.center)
            } else if let setup = cowork.mlxRuntimeInstallMessage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(setup)
                        .font(.ps(11))
                        .foregroundStyle(PrismTheme.accentSecondary)
                }
            } else if cowork.coreStatus == .running, !needsModel {
                Text(L10n.homeTagline)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.keepBrand, systemImage: "building.columns.fill")
                .font(.ps(14, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)

            Text(L10n.keepWelcomeBody)
                .font(.ps(12))
                .foregroundStyle(PrismTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(L10n.keepStep1, done: !needsModel)
                stepRow(L10n.keepStep2, done: false)
                stepRow(L10n.keepStep3, done: false)
            }

            if !needsModel {
                Button(L10n.t("Got it — start asking", "Compris — je commence")) {
                    dismissedWelcome = true
                    cowork.requestComposerFocus()
                }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PrismTheme.accentGradient)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .prismGlass(cornerRadius: 18, padding: 0)
    }

    private func stepRow(_ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(done ? PrismTheme.signalAllow : PrismTheme.textTertiary)
            Text(text)
                .font(.ps(12, weight: .medium))
                .foregroundStyle(PrismTheme.textPrimary)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.connectModel, systemImage: "cpu")
                .font(.ps(13, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
            Text(L10n.connectModelDetail)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
            Button(L10n.addModelProvider) { cowork.showProviderSheet = true }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PrismTheme.accentGradient)
                .clipShape(Capsule())
        }
        .padding(16)
        .prismGlass(cornerRadius: 18, padding: 0)
    }

    private var readyHint: some View {
        Text(L10n.keepReadyHint)
            .font(.ps(11))
            .foregroundStyle(PrismTheme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var featureHints: some View {
        HStack(spacing: 10) {
            hint(L10n.hintImages, icon: "photo.on.rectangle.angled")
            hint(L10n.hintFolders, icon: "folder.badge.gearshape")
            hint(L10n.hintCode, icon: "doc.richtext")
        }
    }

    private func hint(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ps(10, weight: .semibold))
            Text(title)
                .font(.ps(10, weight: .medium))
        }
        .foregroundStyle(PrismTheme.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PrismTheme.surfaceMuted.opacity(0.55))
        .clipShape(Capsule())
    }
}
