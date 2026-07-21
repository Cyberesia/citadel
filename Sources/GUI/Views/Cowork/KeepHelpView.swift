import SwiftUI

/// Searchable Keep help sheet — FR/EN via `KeepHelpCatalog`, extensible per-language maps.
struct KeepHelpView: View {
    @EnvironmentObject var cowork: CoworkState
    @EnvironmentObject var router: CitadelShellRouter
    @State private var query = ""
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Divider().opacity(0.35)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(PrismTheme.surfaceMuted.opacity(0.92))
        .prismGlobalInteraction()
        .onAppear {
            if selectedID == nil {
                selectedID = cowork.keepHelpTopicID
                    ?? contextualArticles.first?.id
                    ?? KeepHelpCatalog.all.first?.id
            }
        }
    }

    private var contextualArticles: [KeepHelpArticle] {
        KeepHelpCatalog.articles(forModeRaw: router.coworkMode.rawValue, query: query)
    }

    private var browseArticles: [KeepHelpArticle] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            // Prefer contextual, then the rest of the catalog (deduped).
            var seen = Set<String>()
            var list: [KeepHelpArticle] = []
            for a in contextualArticles + KeepHelpCatalog.all {
                if seen.insert(a.id).inserted { list.append(a) }
            }
            return list
        }
        return KeepHelpCatalog.all.filter { $0.matches(q) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.keepHelpTitle)
                    .font(.ps(16, weight: .bold))
                Spacer()
                Button {
                    cowork.showKeepHelp = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.ps(11, weight: .semibold))
                }
                .buttonStyle(PrismHandButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PrismTheme.textTertiary)
                TextField(L10n.keepHelpSearch, text: $query)
                    .textFieldStyle(.plain)
                    .font(.ps(12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PrismTheme.surfaceMuted.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if query.isEmpty {
                Text(L10n.keepHelpForPage(router.coworkMode.label))
                    .font(.ps(10, weight: .semibold))
                    .foregroundStyle(PrismTheme.textTertiary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
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
                                    .font(.ps(9))
                                    .foregroundStyle(PrismTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedID == article.id ? PrismTheme.accent.opacity(0.18) : .clear)
                            )
                        }
                        .buttonStyle(PrismPlainHandButtonStyle())
                    }
                }
            }

            if browseArticles.isEmpty {
                Text(L10n.keepHelpNoResults)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textSecondary)
                    .padding(.top, 8)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let article = KeepHelpCatalog.article(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(article.category.label)
                        .font(.ps(10, weight: .semibold))
                        .foregroundStyle(PrismTheme.accentSecondary)
                    Text(article.resolvedTitle())
                        .font(.ps(22, weight: .bold))
                        .foregroundStyle(PrismTheme.textPrimary)
                    Text(article.resolvedBody())
                        .font(.ps(13))
                        .foregroundStyle(PrismTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(28)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(PrismTheme.textTertiary)
                Text(L10n.keepHelpPick)
                    .font(.ps(13))
                    .foregroundStyle(PrismTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
