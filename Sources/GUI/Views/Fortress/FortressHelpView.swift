import SwiftUI

/// Searchable Fortress help sheet — FR/EN via `FortressHelpCatalog`.
struct FortressHelpView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: CitadelShellRouter
    @State private var query = ""
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider().opacity(0.25)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .background(PrismTheme.surfaceMuted.opacity(0.92))
        .onAppear {
            selectedID = state.fortressHelpTopicID
                ?? FortressHelpCatalog.articles(forModeRaw: router.fortressMode.rawValue).first?.id
                ?? FortressHelpCatalog.all.first?.id
        }
    }

    private var contextualArticles: [FortressHelpArticle] {
        FortressHelpCatalog.articles(forModeRaw: router.fortressMode.rawValue, query: query)
    }

    private var browseArticles: [FortressHelpArticle] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            var seen = Set<String>()
            var list: [FortressHelpArticle] = []
            for a in contextualArticles + FortressHelpCatalog.all {
                if seen.insert(a.id).inserted { list.append(a) }
            }
            return list
        }
        return FortressHelpCatalog.all.filter { $0.matches(q) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.fortressHelpTitle)
                    .font(.ps(14, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button {
                    state.showFortressHelp = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PrismTheme.textTertiary)
                }
                .buttonStyle(PrismHandButtonStyle())
            }
            .padding(14)

            TextField(L10n.fortressHelpSearch, text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Text(L10n.fortressHelpForPage(router.fortressMode.label))
                .font(.ps(10, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if browseArticles.isEmpty {
                        Text(L10n.fortressHelpNoResults)
                            .font(.ps(12))
                            .foregroundStyle(PrismTheme.textSecondary)
                            .padding(14)
                    } else {
                        ForEach(browseArticles) { article in
                            Button {
                                selectedID = article.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(article.resolvedTitle())
                                        .font(.ps(12, weight: selectedID == article.id ? .semibold : .medium))
                                        .foregroundStyle(PrismTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text(article.category.label)
                                        .font(.ps(10))
                                        .foregroundStyle(PrismTheme.textTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedID == article.id ? PrismTheme.accent.opacity(0.18) : .clear)
                                }
                            }
                            .buttonStyle(PrismPlainHandButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let article = FortressHelpCatalog.article(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.category.label)
                        .font(.ps(11, weight: .semibold))
                        .foregroundStyle(PrismTheme.accentSecondary)
                    Text(article.resolvedTitle())
                        .font(.ps(20, weight: .bold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(article.resolvedBody())
                        .font(.ps(13))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(L10n.fortressHelpPick)
                .font(.ps(13))
                .foregroundStyle(PrismTheme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
