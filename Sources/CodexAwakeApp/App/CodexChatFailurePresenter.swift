import CodexAwakeCore
import Foundation

struct CodexChatFailure: Equatable, Sendable {
    let title: String
    let explanation: String

    var displayText: String { "\(title)\n\(explanation)" }
}

enum CodexChatFailurePresenter {
    static func present(_ error: Error, language: AppLanguage) -> CodexChatFailure {
        guard let error = error as? CodexAwakeError else {
            return failure(
                language,
                "Message was not sent",
                "Codex returned an unexpected error. Check Diagnostics, then try again.",
                "Сообщение не отправлено",
                "Codex вернул неожиданную ошибку. Проверьте Диагностику и повторите отправку."
            )
        }

        switch error {
        case .codexNotFound, .codexNotExecutable:
            return failure(
                language,
                "Codex runtime is unavailable",
                "Choose a working Codex executable in Diagnostics, then retry.",
                "Среда Codex недоступна",
                "Выберите исполняемый файл Codex в Диагностике и повторите отправку."
            )
        case .connectionFailed, .serverStartFailed, .socketPathTooLong,
            .socketOwnedByAnotherProcess, .invalidSocket:
            return failure(
                language,
                "Connection to Codex was lost",
                "Wait for READY or restart the managed server, then press Retry.",
                "Соединение с Codex потеряно",
                "Дождитесь статуса «ГОТОВ» или перезапустите сервер, затем нажмите «Повторить»."
            )
        case .timeout:
            return failure(
                language,
                "Codex did not answer in time",
                "The request remains in this chat. Check the connection and retry it.",
                "Codex не ответил вовремя",
                "Запрос сохранён в этом чате. Проверьте соединение и повторите его."
            )
        case .incompatibleCodex:
            return failure(
                language,
                "This Codex version is incompatible",
                "Update ChatGPT or Codex CLI, restart CodexAwake, and retry.",
                "Эта версия Codex несовместима",
                "Обновите ChatGPT или Codex CLI, перезапустите CodexAwake и повторите."
            )
        case .malformedMessage:
            return failure(
                language,
                "Codex returned an unreadable response",
                "Restart the managed server. Your message is saved and can be retried.",
                "Codex вернул непонятный ответ",
                "Перезапустите сервер. Сообщение сохранено, его можно отправить повторно."
            )
        case .remoteError(_, let message):
            return remoteFailure(message, language: language)
        }
    }

    private static func remoteFailure(_ rawMessage: String, language: AppLanguage) -> CodexChatFailure {
        let message = rawMessage.lowercased()
        if message.contains("usage") || message.contains("limit") {
            return failure(
                language,
                "Codex usage limit reached",
                "Wait until access is restored, then retry this message.",
                "Достигнут лимит Codex",
                "Дождитесь восстановления доступа и повторите это сообщение."
            )
        }
        if message.contains("contextwindow") || message.contains("context window") {
            return failure(
                language,
                "This chat is too long",
                "Start a new chat or shorten the request, then try again.",
                "Этот чат стал слишком длинным",
                "Создайте новый чат или сократите запрос и повторите."
            )
        }
        if message.contains("overloaded") || message.contains("too many failed attempts") {
            return failure(
                language,
                "Codex is temporarily busy",
                "Wait a moment, then retry this message.",
                "Codex временно перегружен",
                "Подождите немного и повторите это сообщение."
            )
        }
        if message.contains("stream") || message.contains("connectionfailed") {
            return failure(
                language,
                "The response connection was interrupted",
                "Your request is saved. Check the network, then retry.",
                "Соединение во время ответа прервалось",
                "Запрос сохранён. Проверьте сеть и повторите."
            )
        }
        if message.contains("unauthorized") || message.contains("authentication") {
            return failure(
                language,
                "Codex sign-in is required",
                "Open Codex or ChatGPT, sign in, restart CodexAwake, and retry.",
                "Нужно войти в Codex",
                "Откройте Codex или ChatGPT, войдите в аккаунт, перезапустите CodexAwake и повторите."
            )
        }
        if message.contains("sandbox") || message.contains("permission") {
            return failure(
                language,
                "The selected permissions are insufficient",
                "Choose Project access or approve the requested operation, then retry.",
                "Выбранных разрешений недостаточно",
                "Выберите доступ к проекту или подтвердите операцию, затем повторите."
            )
        }
        if message.contains("invalid") || message.contains("unknown variant") {
            return failure(
                language,
                "Codex rejected the chat settings",
                "Choose a supported model and permission mode, then retry.",
                "Codex отклонил настройки чата",
                "Выберите поддерживаемую модель и режим доступа, затем повторите."
            )
        }
        return failure(
            language,
            "Codex could not send this message",
            "The request is saved. Check Diagnostics for technical details, then retry.",
            "Codex не смог отправить сообщение",
            "Запрос сохранён. Проверьте технические детали в Диагностике и повторите."
        )
    }

    private static func failure(
        _ language: AppLanguage,
        _ englishTitle: String,
        _ englishExplanation: String,
        _ russianTitle: String,
        _ russianExplanation: String
    ) -> CodexChatFailure {
        .init(
            title: language.text(englishTitle, russianTitle),
            explanation: language.text(englishExplanation, russianExplanation)
        )
    }
}
