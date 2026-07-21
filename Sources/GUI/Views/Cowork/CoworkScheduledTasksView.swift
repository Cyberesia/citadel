import SwiftUI

struct CoworkScheduledTasksView: View {
    @EnvironmentObject var cowork: CoworkState
    @State private var editorJob: CoworkCronJob?
    @State private var showCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.scheduledTasks)
                    .font(.ps(18, weight: .bold))
                Spacer()
                Button(L10n.newScheduledTask) { showCreate = true }
                    .buttonStyle(PrismHandButtonStyle())
            }

            if cowork.cronJobs.isEmpty {
                Text(L10n.cronEmpty)
                    .font(.ps(12))
                    .foregroundStyle(PrismTheme.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cowork.cronJobs) { job in
                            CoworkCronJobRow(job: job, onEdit: { editorJob = job })
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { Task { await cowork.refreshCronJobs() } }
        .sheet(isPresented: $showCreate) {
            CoworkCronJobEditorSheet(job: nil)
                .environmentObject(cowork)
        }
        .sheet(item: $editorJob) { job in
            CoworkCronJobEditorSheet(job: job)
                .environmentObject(cowork)
        }
    }
}

private struct CoworkCronJobRow: View {
    @EnvironmentObject var cowork: CoworkState
    let job: CoworkCronJob
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.ps(13, weight: .semibold))
                Text(job.schedule?.description ?? job.schedule?.expr ?? "—")
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textSecondary)
                if let prompt = job.prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.ps(9))
                        .foregroundStyle(PrismTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { job.enabled ?? true },
                set: { enabled in Task { await cowork.setCronJobEnabled(job.id, enabled: enabled) } }
            ))
            .labelsHidden()
            Button(L10n.runNow) {
                Task { await cowork.runCronJob(job.id) }
            }
            .buttonStyle(PrismHandButtonStyle())
            .font(.ps(10, weight: .semibold))
            Button(L10n.edit) { onEdit() }
                .buttonStyle(PrismHandButtonStyle())
                .font(.ps(10))
            Button {
                Task { await cowork.deleteCronJob(job.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
            }
            .buttonStyle(PrismHandButtonStyle())
            .help(L10n.delete)
        }
        .padding(12)
        .background(PrismTheme.surfaceMuted.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CoworkCronJobEditorSheet: View {
    @EnvironmentObject var cowork: CoworkState
    @Environment(\.dismiss) private var dismiss

    /// nil = create mode, non-nil = edit mode.
    let job: CoworkCronJob?
    @State private var name = ""
    @State private var prompt = ""
    @State private var cronExpr = "0 9 * * *"

    private static let presets: [(label: () -> String, expr: String)] = [
        ({ L10n.cronPresetEvery15 }, "*/15 * * * *"),
        ({ L10n.cronPresetHourly }, "0 * * * *"),
        ({ L10n.cronPresetDaily9 }, "0 9 * * *"),
        ({ L10n.cronPresetWeekdays9 }, "0 9 * * 1-5"),
        ({ L10n.cronPresetMonday9 }, "0 9 * * 1"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(job == nil ? L10n.newScheduledTask : L10n.editScheduledTask)
                .font(.headline)
            TextField(L10n.cronName, text: $name)
            HStack(spacing: 8) {
                TextField(L10n.cronExpression, text: $cronExpr)
                    .font(.ps(12, design: .monospaced))
                Menu(L10n.cronPresets) {
                    ForEach(Self.presets, id: \.expr) { preset in
                        Button(preset.label()) { cronExpr = preset.expr }
                    }
                }
                .frame(width: 130)
            }
            Text(L10n.cronPrompt)
                .font(.ps(11, weight: .semibold))
            TextEditor(text: $prompt)
                .font(.ps(12))
                .frame(minHeight: 120)
            HStack {
                Spacer()
                Button(L10n.cronCancel) { dismiss() }.buttonStyle(PrismHandButtonStyle())
                Button(L10n.cronSave) {
                    Task {
                        if let job {
                            await cowork.updateCronJobDetails(id: job.id, name: name, expr: cronExpr, prompt: prompt)
                        } else {
                            await cowork.createCronJob(name: name, expr: cronExpr, prompt: prompt)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(PrismHandButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || cronExpr.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let job {
                name = job.name
                prompt = job.prompt ?? ""
                cronExpr = job.schedule?.expr ?? "0 9 * * *"
            }
        }
    }
}
