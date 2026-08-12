import CodexAwakeCore
import Foundation

protocol CodexChatClient: Sendable {
    func startThread(cwd: String) async throws -> String
    func startTurn(threadId: String, text: String, cwd: String) async throws -> String
    func interruptTurn(threadId: String, turnId: String) async throws
}

extension AppServerClient: CodexChatClient {}

@MainActor
final class CodexChatSession: ObservableObject {
    @Published private(set) var messages: [CodexChatMessage] = []
    @Published private(set) var threadID: String?
    @Published private(set) var turnID: String?
    @Published private(set) var isSending = false
    @Published private(set) var approvalRequests: [CodexApprovalRequest] = []

    private var language: AppLanguage
    private var generationID: UUID?
    private var approvalContinuations: [Int: CheckedContinuation<JSONValue, Never>] = [:]

    init(language: AppLanguage) {
        self.language = language
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    @discardableResult
    func send(
        _ prompt: String,
        client: any CodexChatClient,
        workspacePath: String,
        unavailableReason: String?
    ) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return false }
        guard unavailableReason == nil else {
            appendSystemMessage(unavailableReason ?? t("Codex is not ready yet.", "Codex пока не готов."))
            return false
        }

        let currentGeneration = UUID()
        generationID = currentGeneration
        isSending = true
        messages.append(.init(role: .user, text: text))

        Task {
            do {
                var activeThreadID = threadID
                if activeThreadID == nil {
                    activeThreadID = try await client.startThread(cwd: workspacePath)
                    guard generationID == currentGeneration else { return }
                    threadID = activeThreadID
                }
                guard let activeThreadID else { throw CodexAwakeError.malformedMessage }
                let startedTurnID = try await client.startTurn(
                    threadId: activeThreadID,
                    text: text,
                    cwd: workspacePath
                )
                guard generationID == currentGeneration else { return }
                turnID = startedTurnID
            } catch {
                guard generationID == currentGeneration else { return }
                generationID = nil
                isSending = false
                appendSystemMessage(SafeDisplay.sanitizedError(error))
            }
        }
        return true
    }

    func interrupt(client: any CodexChatClient) {
        guard let threadID, let turnID else { return }
        Task {
            do {
                try await client.interruptTurn(threadId: threadID, turnId: turnID)
            } catch {
                appendSystemMessage(SafeDisplay.sanitizedError(error))
            }
        }
    }

    func reset(client: (any CodexChatClient)?) {
        if let client, let threadID, let turnID {
            Task {
                do {
                    try await client.interruptTurn(threadId: threadID, turnId: turnID)
                } catch {
                    // A reset is already authoritative locally; a disconnected server needs no UI error.
                }
            }
        }
        generationID = nil
        threadID = nil
        turnID = nil
        isSending = false
        messages.removeAll()
    }

    func handle(_ event: AppServerEvent) {
        switch event {
        case .agentMessageDelta(let eventThreadID, _, let itemID, let delta):
            guard eventThreadID == threadID else { return }
            if let index = messages.firstIndex(where: { $0.itemId == itemID }) {
                messages[index].text += delta
                messages[index].isStreaming = true
            } else {
                messages.append(
                    .init(
                        role: .assistant,
                        text: delta,
                        itemId: itemID,
                        isStreaming: true
                    ))
            }

        case .agentMessageCompleted(let eventThreadID, _, let itemID, let text, let phase):
            guard eventThreadID == threadID else { return }
            if let index = messages.firstIndex(where: { $0.itemId == itemID }) {
                messages[index].text = text
                messages[index].phase = phase
                messages[index].isStreaming = false
            } else {
                messages.append(
                    .init(
                        role: .assistant,
                        text: text,
                        itemId: itemID,
                        phase: phase
                    ))
            }

        case .turnCompleted(let key, let status):
            guard key.threadId == threadID,
                turnID == nil || key.turnId == turnID
            else { return }
            generationID = nil
            turnID = nil
            isSending = false
            for index in messages.indices where messages[index].isStreaming {
                messages[index].isStreaming = false
            }
            if let status, status != "completed", status != "interrupted" {
                appendSystemMessage(
                    t(
                        "Codex turn ended with status: \(status).",
                        "Ход Codex завершён со статусом: \(status)."
                    ))
            }

        case .runtimeError(let eventThreadID, let message):
            guard eventThreadID == nil || eventThreadID == threadID else { return }
            appendSystemMessage(message)

        default:
            break
        }
    }

    func handleServerRequest(_ request: AppServerServerRequest) async -> JSONValue? {
        let kind: CodexApprovalKind
        switch request.method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        default: return nil
        }

        let approval = CodexApprovalRequest(
            id: request.id,
            kind: kind,
            title: approvalTitle(kind: kind, params: request.params),
            detail: approvalDetail(kind: kind, params: request.params),
            threadId: request.params?["threadId"]?.stringValue,
            turnId: request.params?["turnId"]?.stringValue
        )
        return await withCheckedContinuation { continuation in
            approvalRequests.append(approval)
            approvalContinuations[request.id] = continuation
        }
    }

    func resolve(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        approvalRequests.removeAll { $0.id == request.id }
        approvalContinuations.removeValue(forKey: request.id)?.resume(
            returning: .string(decision.rawValue))
    }

    func cancelPendingApprovals() {
        let continuations = approvalContinuations.values
        approvalContinuations.removeAll()
        approvalRequests.removeAll()
        for continuation in continuations {
            continuation.resume(returning: .string(CodexApprovalDecision.cancel.rawValue))
        }
    }

    func markDisconnected(_ message: String) {
        guard isSending else { return }
        generationID = nil
        turnID = nil
        isSending = false
        appendSystemMessage(message)
    }

    func markUnavailable(_ message: String) {
        appendSystemMessage(message)
    }

    private func approvalTitle(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let host = params?["networkApprovalContext"]?["host"]?.stringValue {
            return t("Allow network access to \(host)?", "Разрешить сетевой доступ к \(host)?")
        }
        return kind == .command
            ? t("Allow this command?", "Разрешить эту команду?")
            : t("Allow these file changes?", "Разрешить эти изменения файлов?")
    }

    private func approvalDetail(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let reason = params?["reason"]?.stringValue, !reason.isEmpty {
            return String(reason.prefix(600))
        }
        if kind == .command {
            if let command = params?["command"]?.stringValue {
                return String(command.prefix(600))
            }
            if let command = params?["command"]?.arrayValue?.compactMap(\.stringValue), !command.isEmpty {
                return String(command.joined(separator: " ").prefix(600))
            }
            return t(
                "Codex wants to run a command in the selected workspace.",
                "Codex хочет выполнить команду в выбранном проекте."
            )
        }
        if let root = params?["grantRoot"]?.stringValue {
            return t("Codex wants to write inside \(root).", "Codex хочет записать данные в \(root).")
        }
        return t(
            "Codex wants to apply file changes in the selected workspace.",
            "Codex хочет изменить файлы в выбранном проекте."
        )
    }

    private func appendSystemMessage(_ text: String) {
        guard messages.last?.role != .system || messages.last?.text != text else { return }
        messages.append(.init(role: .system, text: String(text.prefix(500))))
    }

    private func t(_ english: String, _ russian: String) -> String {
        language.text(english, russian)
    }
}
