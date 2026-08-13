import CodexAwakeCore
import SwiftUI

struct CodexChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var prompt = ""
    @State private var confirmsFullAccess = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            settingsBar

            VSplitView {
                timeline
                    .frame(minHeight: 220)
                if !model.chatTools.isEmpty {
                    ChatActivityView(
                        activities: model.chatTools,
                        language: model.appLanguage
                    )
                    .frame(minHeight: 92, idealHeight: 132, maxHeight: 240)
                }
            }

            composer
        }
        .padding(18)
        .background(CockpitPanel(cornerRadius: 28))
        .confirmationDialog(
            t("Allow unrestricted access?", "Разрешить полный доступ?"),
            isPresented: $confirmsFullAccess,
            titleVisibility: .visible
        ) {
            Button(t("Use Full Access", "Включить полный доступ"), role: .destructive) {
                model.setChatPermissionMode(.fullAccess)
            }
            Button(t("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(
                t(
                    "Codex will be able to read and change files outside the selected project and run commands without the workspace sandbox. Individual dangerous operations can still request confirmation.",
                    "Codex сможет читать и изменять файлы вне выбранного проекта и выполнять команды без песочницы проекта. Для отдельных опасных операций подтверждение всё равно может быть запрошено."
                )
            )
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(t("Chat with Codex", "Чат с Codex"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    ChatStatusPill(
                        text: model.appServerState == .running
                            ? t("READY", "ГОТОВ")
                            : t("OFFLINE", "НЕ В СЕТИ"),
                        color: serverAccent
                    )
                    if model.chatQueuedCount > 0 {
                        ChatStatusPill(
                            text: t(
                                "QUEUE \(model.chatQueuedCount)",
                                "ОЧЕРЕДЬ \(model.chatQueuedCount)"
                            ),
                            color: CockpitPalette.amber
                        )
                    }
                }
                Text(
                    t(
                        "Streamed local Codex session · restored after restart",
                        "Потоковая локальная сессия Codex · восстановление после перезапуска"
                    )
                )
                .font(.caption)
                .foregroundStyle(CockpitPalette.muted)
            }

            Spacer()

            Menu {
                if model.chatConversations.isEmpty {
                    Text(t("No saved chats", "Нет сохранённых чатов"))
                } else {
                    ForEach(model.chatConversations.sorted(by: { $0.updatedAt > $1.updatedAt })) { conversation in
                        Button {
                            model.continueChat(conversation.id)
                            promptFocused = true
                        } label: {
                            Label(
                                conversation.title,
                                systemImage: conversation.id == model.activeChatConversationID
                                    ? "checkmark.circle.fill"
                                    : "bubble.left"
                            )
                        }
                        .disabled(model.chatIsSending)
                    }
                }
            } label: {
                Label(t("History", "История"), systemImage: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                model.newChat()
                promptFocused = true
            } label: {
                Label(t("New chat", "Новый чат"), systemImage: "plus")
            }
            .buttonStyle(CockpitSecondaryButtonStyle())
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 11)
    }

    private var settingsBar: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseWorkspace()
            } label: {
                Label(workspaceName, systemImage: "folder")
                    .lineLimit(1)
            }
            .buttonStyle(CockpitSecondaryButtonStyle())
            .help(model.workspacePath ?? t("Choose a project", "Выберите проект"))

            Picker(
                t("Model", "Модель"),
                selection: Binding(
                    get: { model.chatSelectedModelID ?? "" },
                    set: { model.setChatModel($0.isEmpty ? nil : $0) }
                )
            ) {
                Text(t("Automatic", "Автоматически")).tag("")
                ForEach(model.chatModelOptions) { option in
                    Text(option.displayName).tag(option.model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .help(t("Codex model", "Модель Codex"))

            Picker(
                t("Reasoning", "Рассуждение"),
                selection: Binding(
                    get: { model.chatSelectedReasoningEffort ?? "" },
                    set: { model.setChatReasoningEffort($0.isEmpty ? nil : $0) }
                )
            ) {
                Text(t("Model default", "По умолчанию модели")).tag("")
                ForEach(model.chatReasoningOptions, id: \.id) { option in
                    Text(reasoningTitle(option.id)).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
            .help(t("Reasoning effort", "Глубина рассуждений"))

            Menu {
                permissionButton(.readOnly)
                permissionButton(.workspaceWrite)
                Divider()
                Button(role: .destructive) {
                    confirmsFullAccess = true
                } label: {
                    Label(
                        permissionTitle(.fullAccess),
                        systemImage: model.chatPermissionMode == .fullAccess ? "checkmark" : "lock.open"
                    )
                }
            } label: {
                Label(permissionTitle(model.chatPermissionMode), systemImage: permissionIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(permissionDescription(model.chatPermissionMode))

            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 5)
        .padding(.bottom, 10)
        .disabled(model.chatIsSending)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    if model.chatMessages.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.chatMessages) { message in
                            ReliableChatMessageRow(
                                message: message,
                                language: model.appLanguage,
                                retry: { model.retryMessage(message.id) }
                            )
                            .id(message.id)
                        }
                    }

                    if model.chatIsSending,
                        !model.chatMessages.contains(where: { $0.isStreaming })
                    {
                        ReliableThinkingIndicator(language: model.appLanguage)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 22)
            }
            .background(CockpitPalette.canvas.opacity(0.56), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(CockpitPalette.separator.opacity(0.58)))
            .onChange(of: model.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.chatMessages.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.chatIsSending) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(CockpitPalette.ice)
                .frame(width: 78, height: 78)
                .background(CockpitPalette.ice.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(CockpitPalette.ice.opacity(0.18)))
            Text(
                model.workspacePath == nil
                    ? t("Choose a project", "Выберите проект")
                    : t("What would you like to build?", "Что вы хотите сделать?")
            )
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(emptyDescription)
                .font(.system(size: 12))
                .foregroundStyle(CockpitPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
            if model.workspacePath == nil {
                Button(t("Choose Project…", "Выбрать проект…")) { model.chooseWorkspace() }
                    .buttonStyle(CockpitPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    t(
                        "Ask Codex to inspect, explain, build, or fix…",
                        "Попросите Codex проверить, объяснить, собрать или исправить…"
                    ),
                    text: $prompt,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...7)
                .focused($promptFocused)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
                .background(CockpitPalette.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CockpitPalette.separator.opacity(0.72)))
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        prompt.append("\n")
                        return .handled
                    }
                    if canSend { submitPrompt() }
                    return .handled
                }

                if model.chatIsSending {
                    Button {
                        model.interruptChat()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(CockpitDangerButtonStyle())
                    .disabled(model.chatTurnID == nil)
                    .help(t("Stop current task", "Остановить текущую задачу"))
                }

                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: model.chatIsSending ? "tray.and.arrow.down.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(CockpitPrimaryButtonStyle())
                .disabled(!canSend)
                .help(
                    model.chatIsSending
                        ? t("Add message to queue", "Добавить сообщение в очередь")
                        : t("Send to Codex", "Отправить в Codex")
                )
            }

            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                Text(composerStatus)
                Spacer()
                if let warning = model.chatPersistenceWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(CockpitPalette.amber)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(model.chatUnavailableReason == nil ? CockpitPalette.muted : CockpitPalette.amber)
            .padding(.leading, 9)
        }
        .padding(.top, 13)
        .padding(.horizontal, 5)
    }

    private func permissionButton(_ mode: CodexPermissionMode) -> some View {
        Button {
            model.setChatPermissionMode(mode)
        } label: {
            Label(
                permissionTitle(mode),
                systemImage: model.chatPermissionMode == mode ? "checkmark" : "lock"
            )
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if model.chatIsSending,
            !model.chatMessages.contains(where: { $0.isStreaming })
        {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("thinking", anchor: .bottom) }
        } else if let last = model.chatMessages.last {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private func submitPrompt() {
        if model.sendPrompt(prompt) { prompt = "" }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.workspacePath != nil
    }

    private var composerStatus: String {
        if model.chatIsSending {
            return t(
                "Codex is busy · Enter adds the message to queue · Shift+Enter adds a line",
                "Codex занят · Enter добавит сообщение в очередь · Shift+Enter добавит строку"
            )
        }
        return model.chatUnavailableReason
            ?? t("Enter to send · Shift+Enter for a new line", "Enter — отправить · Shift+Enter — новая строка")
    }

    private var statusIcon: String {
        if model.chatQueuedCount > 0 { return "tray.full" }
        return model.chatUnavailableReason == nil ? "return" : "exclamationmark.circle"
    }

    private var workspaceName: String {
        guard let workspacePath = model.workspacePath else {
            return t("Choose project", "Выбрать проект")
        }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    private var emptyDescription: String {
        if model.workspacePath == nil {
            return t(
                "Choose a working folder. The selection, messages, and queue are restored after restart.",
                "Выберите рабочую папку. Выбор, сообщения и очередь восстановятся после перезапуска."
            )
        }
        return t(
            "Messages stream here, tools and changed file paths appear below, and sensitive actions ask for confirmation.",
            "Ответ поступает потоком, инструменты и пути изменённых файлов появляются ниже, а опасные действия требуют подтверждения."
        )
    }

    private var permissionIcon: String {
        switch model.chatPermissionMode {
        case .readOnly: "eye"
        case .workspaceWrite: "folder.badge.gearshape"
        case .fullAccess: "lock.open"
        }
    }

    private func permissionTitle(_ mode: CodexPermissionMode) -> String {
        switch mode {
        case .readOnly: t("Read only", "Только чтение")
        case .workspaceWrite: t("Project access", "Доступ к проекту")
        case .fullAccess: t("Full access", "Полный доступ")
        }
    }

    private func permissionDescription(_ mode: CodexPermissionMode) -> String {
        switch mode {
        case .readOnly:
            t("No file changes or network access", "Без изменения файлов и доступа к сети")
        case .workspaceWrite:
            t("Write only inside the selected project", "Запись только внутри выбранного проекта")
        case .fullAccess:
            t("Unrestricted file-system access", "Неограниченный доступ к файлам")
        }
    }

    private func reasoningTitle(_ effort: String) -> String {
        switch effort {
        case "none": t("None", "Без рассуждений")
        case "minimal": t("Minimal", "Минимально")
        case "low": t("Low", "Низкая")
        case "medium": t("Medium", "Средняя")
        case "high": t("High", "Высокая")
        case "xhigh": t("Extra high", "Очень высокая")
        default: effort
        }
    }

    private var serverAccent: Color {
        switch model.appServerState {
        case .running: CockpitPalette.ice
        case .failed: CockpitPalette.danger
        case .reconnecting, .starting: CockpitPalette.amber
        default: CockpitPalette.muted
        }
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}
