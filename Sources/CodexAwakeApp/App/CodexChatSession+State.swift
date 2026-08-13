import CodexAwakeCore
import Foundation

extension CodexChatSession {
    var activeConversationIndex: Int? {
        guard let activeConversationID else { return nil }
        return conversations.firstIndex { $0.id == activeConversationID }
    }

    func conversationIndex(threadId: String) -> Int? {
        conversations.firstIndex { $0.threadId == threadId }
    }

    func ensureConversation(settings: CodexChatRequestSettings) {
        guard let activeConversationIndex else {
            createConversation(settings: settings)
            return
        }
        if conversations[activeConversationIndex].settings.workspacePath != settings.workspacePath {
            createConversation(settings: settings)
        }
    }

    func createConversation(settings: CodexChatRequestSettings) {
        let conversation = CodexConversation(
            title: t("New chat", "Новый чат"),
            settings: settings
        )
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        turnID = nil
        currentMessageID = nil
        isSending = false
        persistSoon()
    }

    func createConversation(workspacePath: String) {
        createConversation(settings: .init(workspacePath: workspacePath))
    }

    func updateSettings(_ update: (inout CodexChatRequestSettings) -> Void) {
        guard let index = activeConversationIndex else { return }
        update(&conversations[index].settings)
        conversations[index].updatedAt = Date()
        persistSoon()
    }

    func updateTitleIfNeeded(at index: Int, prompt: String) {
        guard conversations[index].messages.filter({ $0.role == .user }).count == 1 else { return }
        let singleLine = prompt.replacingOccurrences(of: "\n", with: " ")
        conversations[index].title = String(singleLine.prefix(54))
    }

    func applyDefaultModelIfNeeded() {
        guard let index = activeConversationIndex,
            let fallback = modelOptions.first(where: \.isDefault) ?? modelOptions.first
        else { return }
        let selected = modelOptions.first {
            $0.id == conversations[index].settings.modelID
                || $0.model == conversations[index].settings.modelID
        }
        let model = selected ?? fallback
        conversations[index].settings.modelID = model.model
        if !model.reasoningOptions.contains(where: {
            $0.id == conversations[index].settings.reasoningEffort
        }) {
            conversations[index].settings.reasoningEffort = model.defaultReasoningEffort
        }
        persistSoon()
    }

    func appendSystemMessage(_ text: String) {
        guard let index = activeConversationIndex else { return }
        guard
            conversations[index].messages.last?.role != .system
                || conversations[index].messages.last?.text != text
        else { return }
        conversations[index].messages.append(
            .init(role: .system, text: String(text.prefix(1_000)))
        )
        conversations[index].updatedAt = Date()
        persistSoon()
    }

    func persistSoon() {
        persistenceTask?.cancel()
        let archive = CodexChatArchive(
            activeConversationID: activeConversationID,
            conversations: conversations
        )
        persistenceTask = Task { [repository] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                try await repository.save(archive)
            } catch is CancellationError {
            } catch {
                self.persistenceWarning = self.t(
                    "Chat history could not be saved.",
                    "Не удалось сохранить историю чата."
                )
            }
        }
    }

    func flushPersistence() async {
        persistenceTask?.cancel()
        persistenceTask = nil
        let archive = CodexChatArchive(
            activeConversationID: activeConversationID,
            conversations: conversations
        )
        do {
            try await repository.save(archive)
        } catch {
            persistenceWarning = t(
                "Chat history could not be saved.",
                "Не удалось сохранить историю чата."
            )
        }
    }
}
