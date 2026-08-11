import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.title2.bold())
            Text("Privacy-safe operational state. Prompts, model responses, tool output, tokens, and credentials are never included.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.diagnostics.snapshot.sanitizedText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy Diagnostics") { model.copyDiagnostics() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Choose Codex Binary…") { model.chooseCodexBinary() }
                Spacer()
                Text("Managed tasks and Codex Desktop presence are tracked separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
}
