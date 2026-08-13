import CodexAwakeCore
import Foundation

extension CodexChatSession {
    func handle(_ event: AppServerEvent) {
        switch event {
        case .turnStarted(let key):
            guard key.threadId == threadID else { return }
            turnID = key.turnId
        case .agentMessageDelta(let threadId, _, let itemId, let delta):
            updateAgentMessage(threadId: threadId, itemId: itemId, delta: delta)
        case .agentMessageCompleted(let threadId, _, let itemId, let text, let phase):
            completeAgentMessage(
                threadId: threadId,
                itemId: itemId,
                text: text,
                phase: phase
            )
        case .itemStarted(let threadId, _, _, let activity):
            if let activity { updateTool(threadId: threadId, activity: activity) }
        case .itemCompleted(let threadId, _, _, let activity):
            if let activity { updateTool(threadId: threadId, activity: activity) }
        case .turnCompleted(let key, let status):
            completeTurn(key: key, status: status)
        case .runtimeError(let threadId, let message):
            if let threadId, conversationIndex(threadId: threadId) == nil { return }
            let failure = CodexChatFailurePresenter.present(
                CodexAwakeError.remoteError(code: -1, message: message),
                language: language
            )
            failCurrentMessage(reason: failure.displayText)
        default:
            break
        }
    }

    func completeTurn(key: TurnKey, status: String?) {
        guard let conversationIndex = conversationIndex(threadId: key.threadId),
            conversations[conversationIndex].id == activeConversationID,
            turnID == nil || key.turnId == turnID
        else { return }

        for messageIndex in conversations[conversationIndex].messages.indices
        where conversations[conversationIndex].messages[messageIndex].isStreaming {
            conversations[conversationIndex].messages[messageIndex].isStreaming = false
        }

        let finalStatus = status ?? "completed"
        if finalStatus == "failed" {
            failCurrentMessage(
                reason: t(
                    "Codex could not complete this request. Review the activity above and press Retry.",
                    "Codex не смог завершить запрос. Проверьте события выше и нажмите «Повторить»."
                )
            )
        } else if finalStatus == "interrupted" {
            appendSystemMessage(t("Task stopped.", "Задача остановлена."))
        }
        isSending = false
        currentMessageID = nil
        turnID = nil
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
        if finalStatus != "failed" { Task { await drainQueue() } }
    }

    func updateAgentMessage(threadId: String, itemId: String, delta: String) {
        guard let conversationIndex = conversationIndex(threadId: threadId) else { return }
        if let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
            $0.itemId == itemId
        }) {
            conversations[conversationIndex].messages[messageIndex].text += delta
            conversations[conversationIndex].messages[messageIndex].isStreaming = true
        } else {
            conversations[conversationIndex].messages.append(
                .init(role: .assistant, text: delta, itemId: itemId, isStreaming: true)
            )
        }
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
    }

    func completeAgentMessage(
        threadId: String,
        itemId: String,
        text: String,
        phase: String?
    ) {
        guard let conversationIndex = conversationIndex(threadId: threadId) else { return }
        if let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
            $0.itemId == itemId
        }) {
            conversations[conversationIndex].messages[messageIndex].text = text
            conversations[conversationIndex].messages[messageIndex].phase = phase
            conversations[conversationIndex].messages[messageIndex].isStreaming = false
        } else {
            conversations[conversationIndex].messages.append(
                .init(role: .assistant, text: text, itemId: itemId, phase: phase)
            )
        }
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
    }

    func updateTool(threadId: String, activity: CodexToolActivity) {
        guard let conversationIndex = conversationIndex(threadId: threadId) else { return }
        if let toolIndex = conversations[conversationIndex].tools.firstIndex(where: {
            $0.id == activity.id
        }) {
            conversations[conversationIndex].tools[toolIndex] = activity.replacingStartDate(
                conversations[conversationIndex].tools[toolIndex].startedAt
            )
        } else {
            conversations[conversationIndex].tools.append(activity)
        }
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
    }
}

private extension CodexToolActivity {
    func replacingStartDate(_ startedAt: Date) -> CodexToolActivity {
        .init(
            id: id,
            turnId: turnId,
            kind: kind,
            title: title,
            detail: detail,
            changedFiles: changedFiles,
            status: status,
            startedAt: startedAt,
            completedAt: status == .running ? nil : Date()
        )
    }
}
