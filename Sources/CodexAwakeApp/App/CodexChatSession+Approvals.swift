import CodexAwakeCore
import Foundation

extension CodexChatSession {
    func handleServerRequest(_ request: AppServerServerRequest) async -> JSONValue? {
        guard request.params?["threadId"]?.stringValue == threadID else { return nil }

        let kind: CodexApprovalKind
        switch request.method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        case "item/permissions/requestApproval": kind = .permissions
        default: return nil
        }

        let approval = CodexApprovalRequest(
            id: request.id,
            kind: kind,
            title: approvalTitle(kind: kind, params: request.params),
            detail: approvalDetail(kind: kind, params: request.params),
            threadId: request.params?["threadId"]?.stringValue,
            turnId: request.params?["turnId"]?.stringValue,
            requestedPermissions: request.params?["permissions"]
        )
        return await withCheckedContinuation { continuation in
            approvalRequests.append(approval)
            approvalContinuations[request.id] = continuation
        }
    }

    func resolve(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        approvalRequests.removeAll { $0.id == request.id }
        let result: JSONValue
        if request.kind == .permissions {
            let permissions =
                decision == .accept || decision == .acceptForSession
                ? request.requestedPermissions ?? .object([:])
                : .object([:])
            result = .object([
                "permissions": permissions,
                "scope": .string(decision == .acceptForSession ? "session" : "turn"),
            ])
        } else {
            result = .object(["decision": .string(decision.rawValue)])
        }
        approvalContinuations.removeValue(forKey: request.id)?.resume(returning: result)
    }

    func cancelPendingApprovals() {
        let pending = approvalContinuations
        approvalContinuations.removeAll()
        let requests = Dictionary(uniqueKeysWithValues: approvalRequests.map { ($0.id, $0) })
        approvalRequests.removeAll()
        for (id, continuation) in pending {
            let result: JSONValue =
                requests[id]?.kind == .permissions
                ? .object(["permissions": .object([:]), "scope": .string("turn")])
                : .object(["decision": .string(CodexApprovalDecision.cancel.rawValue)])
            continuation.resume(returning: result)
        }
    }

    private func approvalTitle(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let host = params?["networkApprovalContext"]?["host"]?.stringValue {
            return t("Allow network access to \(host)?", "Разрешить сетевой доступ к \(host)?")
        }
        switch kind {
        case .command: return t("Allow this command?", "Разрешить эту команду?")
        case .fileChange: return t("Allow these file changes?", "Разрешить эти изменения файлов?")
        case .permissions: return t("Grant additional permissions?", "Предоставить дополнительные разрешения?")
        }
    }

    private func approvalDetail(kind: CodexApprovalKind, params: JSONValue?) -> String {
        if let reason = params?["reason"]?.stringValue, !reason.isEmpty {
            return String(reason.prefix(600))
        }
        switch kind {
        case .command:
            if let command = params?["command"]?.stringValue {
                return String(command.prefix(600))
            }
            if let command = params?["command"]?.arrayValue?.compactMap(\.stringValue),
                !command.isEmpty
            {
                return String(command.joined(separator: " ").prefix(600))
            }
            return t(
                "Codex wants to run a command in the selected project.",
                "Codex хочет выполнить команду в выбранном проекте."
            )
        case .fileChange:
            if let root = params?["grantRoot"]?.stringValue {
                return t("Codex wants to write inside \(root).", "Codex хочет записать данные в \(root).")
            }
            return t(
                "Codex wants to apply file changes in the selected project.",
                "Codex хочет изменить файлы в выбранном проекте."
            )
        case .permissions:
            return t(
                "Codex requests extra file-system or network access for this operation.",
                "Codex запрашивает дополнительный доступ к файлам или сети для этой операции."
            )
        }
    }
}
