import CodexAwakeCore
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
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.diagnostics.snapshot.sanitizedText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    Text(t("Recent operational events", "Последние события"))
                        .font(.headline)
                    if model.diagnostics.events.isEmpty {
                        Text(t("No events yet", "Событий пока нет"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.diagnostics.events.prefix(20)) { event in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: eventSymbol(event.level))
                                    .foregroundStyle(eventColor(event.level))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.appLanguage.text(event.english, event.russian))
                                        .textSelection(.enabled)
                                    Text(event.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(8)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(t("Copy Diagnostics", "Скопировать диагностику")) { model.copyDiagnostics() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(t("Export Report…", "Экспортировать отчёт…")) { model.exportDiagnostics() }
                Button(t("Choose Codex Binary…", "Выбрать исполняемый файл Codex…")) { model.chooseCodexBinary() }
                if model.closedLidProtection.helperInstalled {
                    if !model.closedLidProtection.helperReachable {
                        Button(t("Retry Helper Connection", "Повторить подключение к helper")) {
                            model.retryClosedLidHelperConnection()
                        }
                        .disabled(model.closedLidHelperActionInProgress)
                        Button(t("Repair / Update Closed-Lid Helper…", "Восстановить / обновить Closed-Lid helper…")) {
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

    private func eventSymbol(_ level: OperationalEvent.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func eventColor(_ level: OperationalEvent.Level) -> Color {
        switch level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
