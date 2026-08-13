import CodexAwakeCore
import Foundation

extension CodexChatSession {
    func refreshModels() async {
        guard let client else { return }
        do {
            let loadedModels = try await client.listModels()
            guard self.client != nil else { return }
            modelOptions = loadedModels
            applyDefaultModelIfNeeded()
        } catch {
            modelOptions = []
        }
    }

    func drainQueue() async {
        guard !isSending, let client, let conversationIndex = activeConversationIndex,
            let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                $0.delivery == .queued
            })
        else { return }

        let message = conversations[conversationIndex].messages[messageIndex]
        let settings = message.requestSettings ?? conversations[conversationIndex].settings
        guard FileManager.default.fileExists(atPath: settings.workspacePath) else {
            failMessage(
                conversationIndex: conversationIndex,
                messageID: message.id,
                reason: t(
                    "The selected project folder no longer exists. Choose another folder and retry.",
                    "Выбранная папка проекта больше не существует. Выберите другую папку и повторите."
                )
            )
            return
        }

        isSending = true
        currentMessageID = message.id
        conversations[conversationIndex].messages[messageIndex].delivery = .sending
        persistSoon()

        do {
            let threadId = try await ensureThread(
                client: client,
                conversationIndex: conversationIndex,
                settings: settings
            )
            let startedTurnID = try await client.startTurn(
                threadId: threadId,
                messageID: message.id,
                text: message.text,
                settings: settings
            )
            guard activeConversationID == conversations[conversationIndex].id,
                currentMessageID == message.id
            else { return }
            turnID = startedTurnID
            markMessageSent(conversationIndex: conversationIndex, messageID: message.id)
            persistSoon()
        } catch {
            let failure = CodexChatFailurePresenter.present(error, language: language)
            failMessage(
                conversationIndex: conversationIndex,
                messageID: message.id,
                reason: failure.displayText
            )
            isSending = false
            currentMessageID = nil
            turnID = nil
        }
    }

    func failCurrentMessage(reason: String) {
        guard let currentMessageID, let conversationIndex = activeConversationIndex else {
            isSending = false
            turnID = nil
            return
        }
        failMessage(
            conversationIndex: conversationIndex,
            messageID: currentMessageID,
            reason: reason
        )
        isSending = false
        self.currentMessageID = nil
        turnID = nil
    }

    func failMessage(conversationIndex: Int, messageID: UUID, reason: String) {
        guard conversations.indices.contains(conversationIndex),
            let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else { return }
        conversations[conversationIndex].messages[messageIndex].delivery = .failed
        conversations[conversationIndex].messages[messageIndex].failureReason = reason
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
    }

    private func ensureThread(
        client: any CodexChatClient,
        conversationIndex: Int,
        settings: CodexChatRequestSettings
    ) async throws -> String {
        if let threadId = conversations[conversationIndex].threadId {
            if !resumedThreadIDs.contains(threadId) {
                let resumed = try await client.resumeThread(threadId: threadId, settings: settings)
                conversations[conversationIndex].threadId = resumed
                resumedThreadIDs.insert(resumed)
                persistSoon()
                return resumed
            }
            return threadId
        }

        let threadId = try await client.startThread(settings: settings)
        conversations[conversationIndex].threadId = threadId
        resumedThreadIDs.insert(threadId)
        persistSoon()
        return threadId
    }

    private func markMessageSent(conversationIndex: Int, messageID: UUID) {
        guard
            let index = conversations[conversationIndex].messages.firstIndex(where: {
                $0.id == messageID
            })
        else { return }
        conversations[conversationIndex].messages[index].delivery = .sent
    }
}
