import CodexAwakeCore
import Foundation

protocol CodexChatClient: Sendable {
    func listModels() async throws -> [CodexModelOption]
    func startThread(settings: CodexChatRequestSettings) async throws -> String
    func resumeThread(threadId: String, settings: CodexChatRequestSettings) async throws -> String
    func startTurn(
        threadId: String,
        messageID: UUID,
        text: String,
        settings: CodexChatRequestSettings
    ) async throws -> String
    func interruptTurn(threadId: String, turnId: String) async throws
}

extension AppServerClient: CodexChatClient {}

@MainActor
final class CodexChatSession: ObservableObject {
    @Published var conversations: [CodexConversation] = []
    @Published var activeConversationID: UUID?
    @Published var turnID: String?
    @Published var isSending = false
    @Published var modelOptions: [CodexModelOption] = []
    @Published var approvalRequests: [CodexApprovalRequest] = []
    @Published var persistenceWarning: String?

    var language: AppLanguage
    var approvalContinuations: [Int: CheckedContinuation<JSONValue, Never>] = [:]

    let repository: any CodexChatPersisting
    var client: (any CodexChatClient)?
    var resumedThreadIDs: Set<String> = []
    var currentMessageID: UUID?
    var persistenceTask: Task<Void, Never>?
    var didRestore = false

    init(
        language: AppLanguage,
        repository: any CodexChatPersisting = FileCodexChatRepository()
    ) {
        self.language = language
        self.repository = repository
    }

    var messages: [CodexChatMessage] { activeConversation?.messages ?? [] }
    var tools: [CodexToolActivity] { activeConversation?.tools ?? [] }
    var threadID: String? { activeConversation?.threadId }
    var queuedCount: Int { messages.count { $0.delivery == .queued } }
    var activeConversation: CodexConversation? {
        guard let activeConversationID else { return nil }
        return conversations.first { $0.id == activeConversationID }
    }

    var selectedModelID: String? { activeConversation?.settings.modelID }
    var selectedReasoningEffort: String? { activeConversation?.settings.reasoningEffort }
    var permissionMode: CodexPermissionMode {
        activeConversation?.settings.permissionMode ?? .workspaceWrite
    }

    var reasoningOptions: [CodexReasoningOption] {
        guard let selectedModelID,
            let model = modelOptions.first(where: { $0.id == selectedModelID || $0.model == selectedModelID })
        else { return [] }
        return model.reasoningOptions
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    func restore(defaultWorkspacePath: String?) async {
        guard !didRestore else { return }
        didRestore = true
        do {
            let archive = try await repository.load()
            conversations = archive.conversations
            activeConversationID = archive.activeConversationID
            if !conversations.contains(where: { $0.id == activeConversationID }) {
                activeConversationID = conversations.first?.id
            }
        } catch {
            persistenceWarning = t(
                "Previous chat history could not be restored. New chats will still work.",
                "Не удалось восстановить прошлые чаты. Новые чаты продолжат работать."
            )
        }

        if activeConversationID == nil, let defaultWorkspacePath {
            createConversation(workspacePath: defaultWorkspacePath)
        }
    }

    func attach(client: any CodexChatClient) {
        self.client = client
        Task { await refreshModels() }
        Task { await drainQueue() }
    }

    func detach(_ reason: String) {
        client = nil
        resumedThreadIDs.removeAll()
        failCurrentMessage(reason: reason)
    }

    @discardableResult
    func enqueue(
        _ prompt: String,
        settings: CodexChatRequestSettings,
        unavailableReason: String?
    ) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        ensureConversation(settings: settings)
        guard let index = activeConversationIndex else { return false }

        let failureReason = unavailableReason.map {
            t(
                "Message was not sent. \($0)",
                "Сообщение не отправлено. \($0)"
            )
        }
        let message = CodexChatMessage(
            role: .user,
            text: text,
            delivery: failureReason == nil ? .queued : .failed,
            failureReason: failureReason,
            requestSettings: settings
        )
        conversations[index].settings = settings
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        updateTitleIfNeeded(at: index, prompt: text)
        persistSoon()

        if failureReason == nil { Task { await drainQueue() } }
        return true
    }

    func retry(messageID: UUID, unavailableReason: String?) {
        guard let conversationIndex = activeConversationIndex,
            let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        if let unavailableReason {
            conversations[conversationIndex].messages[messageIndex].failureReason = t(
                "Still not sent. \(unavailableReason)",
                "Сообщение всё ещё не отправлено. \(unavailableReason)"
            )
            conversations[conversationIndex].updatedAt = Date()
            persistSoon()
            return
        }
        conversations[conversationIndex].messages[messageIndex].delivery = .queued
        conversations[conversationIndex].messages[messageIndex].failureReason = nil
        conversations[conversationIndex].messages[messageIndex].requestSettings =
            conversations[conversationIndex].settings
        conversations[conversationIndex].updatedAt = Date()
        persistSoon()
        Task { await drainQueue() }
    }

    func interrupt() {
        guard let client, let threadID, let turnID else { return }
        Task {
            do {
                try await client.interruptTurn(threadId: threadID, turnId: turnID)
            } catch {
                appendSystemMessage(CodexChatFailurePresenter.present(error, language: language).displayText)
            }
        }
    }

    func startNewConversation(settings: CodexChatRequestSettings) {
        if isSending {
            interrupt()
            failCurrentMessage(
                reason: t("Stopped to start a new chat.", "Остановлено для создания нового чата."))
        }
        createConversation(settings: settings)
    }

    func selectConversation(_ id: UUID) {
        guard !isSending, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        activeConversationID = id
        conversations[index].updatedAt = Date()
        turnID = nil
        currentMessageID = nil
        persistSoon()
        Task { await drainQueue() }
    }

    func updateWorkspace(_ workspacePath: String) {
        let settings =
            activeConversation?.settings
            ?? .init(workspacePath: workspacePath)
        var updated = settings
        updated.workspacePath = workspacePath
        startNewConversation(settings: updated)
    }

    func selectModel(_ modelID: String?) {
        updateSettings { settings in
            settings.modelID = modelID
            if let modelID,
                let model = modelOptions.first(where: { $0.id == modelID || $0.model == modelID })
            {
                settings.reasoningEffort = model.defaultReasoningEffort
            } else {
                settings.reasoningEffort = nil
            }
        }
    }

    func selectReasoningEffort(_ effort: String?) {
        updateSettings { $0.reasoningEffort = effort }
    }

    func selectPermissionMode(_ mode: CodexPermissionMode) {
        updateSettings { $0.permissionMode = mode }
    }

    func markUnavailable(_ message: String) {
        appendSystemMessage(message)
    }

    func t(_ english: String, _ russian: String) -> String {
        language.text(english, russian)
    }
}
