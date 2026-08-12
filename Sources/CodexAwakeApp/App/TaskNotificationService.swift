import CodexAwakeCore
import Foundation
import UserNotifications

final class TaskNotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Kind {
        case completed
        case attention
        case approval
        case error
    }

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func post(for task: CodexTaskRecord, kind: Kind, language: AppLanguage) {
        center.getNotificationSettings { [center] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.addNotification(to: center, task: task, kind: kind, language: language)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    Self.addNotification(to: center, task: task, kind: kind, language: language)
                }
            default:
                break
            }
        }
    }

    private static func addNotification(
        to center: UNUserNotificationCenter,
        task: CodexTaskRecord,
        kind: Kind,
        language: AppLanguage
    ) {
        let content = UNMutableNotificationContent()
        switch kind {
        case .completed:
            content.title = language.text("Codex task completed", "Задача Codex завершена")
            content.body = task.projectName
        case .approval:
            content.title = language.text("Codex needs approval", "Codex ждёт подтверждения")
            content.body = language.text(
                "Open CodexAwake to review \(task.projectName).",
                "Откройте CodexAwake и проверьте задачу \(task.projectName)."
            )
        case .attention:
            content.title = language.text("Codex needs your attention", "Codex ждёт вашего ответа")
            content.body = task.projectName
        case .error:
            content.title = language.text("Codex task failed", "Ошибка задачи Codex")
            content.body = task.projectName
        }
        content.sound = .default
        content.userInfo = ["taskId": task.id]
        let request = UNNotificationRequest(
            identifier: "task-\(kind)-\(task.id)-\(task.updatedAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
