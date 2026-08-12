import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Diagnostics", "Диагностика"))
                .font(.title2.bold())
            Text(
                t(
                    "Privacy-safe operational state. Prompts, model responses, tool output, tokens, and credentials are never included.",
                    "Безопасное состояние приложения. Запросы, ответы модели, вывод инструментов, токены и данные входа сюда не попадают."
                )
            )
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
                Button(t("Copy Diagnostics", "Скопировать диагностику")) { model.copyDiagnostics() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(t("Choose Codex Binary…", "Выбрать исполняемый файл Codex…")) { model.chooseCodexBinary() }
                if model.closedLidProtection.helperInstalled {
                    if !model.closedLidProtection.helperReachable {
                        Button(t("Retry Helper Connection", "Повторить подключение к helper")) {
                            model.retryClosedLidHelperConnection()
                        }
                        .disabled(model.closedLidHelperActionInProgress)
                        Button(t("Update Helper for This App Version…", "Обновить helper для этой версии…")) {
                            model.installClosedLidHelper()
                        }
                        .disabled(model.closedLidHelperActionInProgress)
                    }
                    Button(t("Remove Closed-Lid Helper…", "Удалить Closed-Lid helper…")) {
                        model.removeClosedLidHelper()
                    }
                } else {
                    Button(t("Install Closed-Lid Helper…", "Установить Closed-Lid helper…")) {
                        model.installClosedLidHelper()
                    }
                    .disabled(model.closedLidHelperActionInProgress)
                }
                Spacer()
                Text(
                    t(
                        "Managed events and privacy-safe Desktop lifecycle markers are tracked separately.",
                        "Управляемые события и безопасные маркеры жизненного цикла Desktop отслеживаются отдельно."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}
