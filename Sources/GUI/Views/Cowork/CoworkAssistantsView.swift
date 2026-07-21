import SwiftUI

struct CoworkAssistantsView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var editingAssistantID: String?
    @State private var showCreateSheet = false

    /// Built-in assistants can't be deleted.
    private static let protectedIDs: Set<String> = ["cowork", "aionui-assistant"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.assistantsTitle)
                    .font(.ps(16, weight: .semibold))
                    .foregroundStyle(PrismTheme.textPrimary)
                Spacer()
                Button(L10n.newAssistant) { showCreateSheet = true }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(11, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text(L10n.assistantsSubtitle)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
                .padding(.horizontal, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(cowork.assistants, id: \.id) { assistant in
                        assistantCard(assistant)
                    }
                }
                .padding(16)
            }
        }
        .onAppear { cowork.startCoreIfNeeded() }
        .sheet(isPresented: Binding(
            get: { editingAssistantID != nil },
            set: { if !$0 { editingAssistantID = nil } }
        )) {
            if let id = editingAssistantID {
                CoworkAssistantEditorView(assistantID: id)
                    .environmentObject(cowork)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CoworkAssistantCreateSheet()
                .environmentObject(cowork)
        }
    }

    private func assistantCard(_ assistant: CoworkAssistant) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                cowork.selectedAssistantID = assistant.id
            } label: {
                cardContent(assistant)
            }
            .buttonStyle(PrismHandButtonStyle())
            HStack {
                Spacer()
                if !assistant.isBuiltin && !Self.protectedIDs.contains(assistant.id) {
                    Button {
                        Task { await cowork.deleteAssistant(assistant.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.ps(9))
                            .foregroundStyle(PrismTheme.textTertiary)
                    }
                    .buttonStyle(PrismHandButtonStyle())
                    .help(L10n.delete)
                }
                Button(L10n.edit) { editingAssistantID = assistant.id }
                    .buttonStyle(PrismHandButtonStyle())
                    .font(.ps(9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func cardContent(_ assistant: CoworkAssistant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: assistant.id == "cowork" ? "sparkles" : "person.crop.circle.fill")
                    .foregroundStyle(PrismTheme.accentSecondary)
                Spacer()
                if cowork.selectedAssistantID == assistant.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PrismTheme.signalAllow)
                }
            }
            Text(assistant.displayName)
                .font(.ps(12, weight: .semibold))
                .foregroundStyle(PrismTheme.textPrimary)
                .lineLimit(2)
            Text(assistant.displaySummary)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(assistant.displayBackendType)
                .font(.ps(9, weight: .bold))
                .foregroundStyle(PrismTheme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cowork.selectedAssistantID == assistant.id
                      ? PrismTheme.accentSoft
                      : PrismTheme.surfaceMuted.opacity(0.45))
        )
    }
}

struct CoworkAssistantCreateSheet: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var rules = ""
    @State private var recommendedPromptsText = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.newAssistant).font(.ps(16, weight: .bold))
            TextField(L10n.assistantName, text: $name)
            TextField(L10n.assistantDescription, text: $description)
            Text(L10n.systemPrompt).font(.ps(11, weight: .semibold))
            TextEditor(text: $rules)
                .font(.ps(12, design: .monospaced))
                .frame(minHeight: 140)
            Text(L10n.recommendedPrompts).font(.ps(11, weight: .semibold))
            TextEditor(text: $recommendedPromptsText)
                .font(.ps(11, design: .monospaced))
                .frame(minHeight: 72)
            HStack {
                Spacer()
                Button(L10n.cronCancel) { dismiss() }
                    .buttonStyle(PrismHandButtonStyle())
                    .disabled(isSaving)
                Button(L10n.cronSave) {
                    Task { await save() }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let prompts = recommendedPromptsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        await cowork.createAssistant(
            name: name,
            description: description,
            rules: rules,
            recommendedPrompts: prompts
        )
        dismiss()
    }
}
