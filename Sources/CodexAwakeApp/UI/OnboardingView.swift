import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pageCount = 3

    var body: some View {
        ZStack {
            CockpitBackground()
            Color(nsColor: .windowBackgroundColor).opacity(0.90)

            VStack(spacing: 0) {
                header
                ScrollView {
                    pageContent
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                footer
            }
            .padding(28)
            .frame(maxWidth: 980, maxHeight: 720)
        }
        .accessibilityElement(children: .contain)
        .onMoveCommand { direction in
            if direction == .left { move(to: page - 1) }
            if direction == .right { move(to: page + 1) }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("CodexAwake")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(t("Welcome setup", "Первоначальная настройка"))
                    .font(.caption)
                    .foregroundStyle(CockpitPalette.muted)
            }

            Spacer()
            LanguageSwitcher(
                selection: Binding(
                    get: { model.appLanguage },
                    set: { model.setAppLanguage($0) }
                ))
            ThemeSwitcher(
                language: model.appLanguage,
                selection: Binding(
                    get: { model.interfaceTheme },
                    set: { model.setInterfaceTheme($0) }
                ))
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch page {
            case 0: welcomePage
            case 1: powerModesPage
            default: preferencesPage
            }
        }
        .id(page)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(CockpitPalette.ice.opacity(0.10))
                Circle()
                    .stroke(CockpitPalette.ice.opacity(0.28), lineWidth: 1)
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(CockpitPalette.ice)
            }
            .frame(width: 112, height: 112)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(t("Your Codex work stays awake", "Работа Codex не прервётся из-за сна"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(
                    t(
                        "CodexAwake protects active tasks, shows their status, and gives you a reliable local Codex chat.",
                        "CodexAwake защищает активные задачи, показывает их статус и предоставляет надёжный локальный чат Codex."
                    )
                )
                .font(.system(size: 14))
                .foregroundStyle(CockpitPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { welcomeFacts }
                VStack(spacing: 10) { welcomeFacts }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var welcomeFacts: some View {
        OnboardingFact(
            icon: "lock.shield",
            title: t("Private by design", "Приватность по умолчанию"),
            detail: t("External chat text is not read", "Текст внешних чатов не читается")
        )
        OnboardingFact(
            icon: "waveform.path.ecg",
            title: t("Activity-aware", "Учитывает активность"),
            detail: t("Protection follows real tasks", "Защита следует за реальными задачами")
        )
        OnboardingFact(
            icon: "bubble.left.and.bubble.right",
            title: t("Reliable chat", "Надёжный чат"),
            detail: t("Streaming, queue, recovery", "Поток, очередь, восстановление")
        )
    }

    private var powerModesPage: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(t("Three power modes, clearly explained", "Три понятных режима питания"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(
                    t(
                        "Combine them as needed. Protection is applied only while CodexAwake has a reason to keep working.",
                        "Комбинируйте их как удобно. Защита применяется только пока у CodexAwake есть причина продолжать работу."
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(CockpitPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { powerModeCards }
                VStack(spacing: 10) { powerModeCards }
            }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var powerModeCards: some View {
        OnboardingPowerMode(
            number: "01",
            icon: "moon.zzz.fill",
            title: t("Keep Mac awake", "Не давать Mac уснуть"),
            detail: t(
                "Background Codex work continues. The display may still turn off if display protection is disabled.",
                "Фоновая работа Codex продолжается. Экран может погаснуть, если его защита выключена."
            ),
            badge: t("No password", "Без пароля")
        )
        OnboardingPowerMode(
            number: "02",
            icon: "display",
            title: t("Keep display on", "Не выключать экран"),
            detail: t(
                "Prevents idle dimming while protection is active. It does not override closing the MacBook lid.",
                "Не даёт экрану погаснуть при активной защите, но не отменяет сон при закрытии крышки."
            ),
            badge: t("No password", "Без пароля")
        )
        OnboardingPowerMode(
            number: "03",
            icon: "lock.open.display",
            title: t("Closed-lid mode", "Работа с закрытой крышкой"),
            detail: t(
                "A narrow bundled service keeps the whole Mac awake with the lid closed and restores normal sleep afterward.",
                "Узкая встроенная служба поддерживает работу всего Mac с закрытой крышкой и затем возвращает обычный сон."
            ),
            badge: t("One-time admin approval", "Одно подтверждение администратора")
        )
    }

    private var preferencesPage: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(t("Choose a comfortable default", "Выберите удобное поведение"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(
                    t(
                        "Every card is clickable and can be changed later in the Cockpit.",
                        "Карточки полностью кликабельны, а настройки всегда можно изменить в Cockpit."
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(CockpitPalette.muted)
            }

            VStack(spacing: 10) {
                PremiumToggleCard(
                    title: t("Protect active Codex work", "Защищать активную работу Codex"),
                    subtitle: t(
                        "Automatically applies the selected power modes",
                        "Автоматически применяет выбранные режимы питания"
                    ),
                    icon: "bolt.shield",
                    accent: CockpitPalette.ice,
                    language: model.appLanguage,
                    isOn: Binding(
                        get: { model.autoKeepAwake },
                        set: { model.setAutoKeepAwake($0) }
                    )
                )
                PremiumToggleCard(
                    title: t("Sleep between tasks", "Разрешать сон между задачами"),
                    subtitle: t(
                        "When Codex is open but idle, normal macOS timers resume",
                        "Если Codex открыт, но бездействует, снова работают таймеры macOS"
                    ),
                    icon: "moon.stars",
                    accent: CockpitPalette.violetSoft,
                    language: model.appLanguage,
                    isOn: Binding(
                        get: { model.allowSleepWhenCodexIdle },
                        set: { model.setAllowSleepWhenCodexIdle($0) }
                    )
                )
                PremiumToggleCard(
                    title: t("Compact Menu Bar", "Компактное меню"),
                    subtitle: t(
                        "Show status and essential actions first",
                        "Сначала показывать статус и основные действия"
                    ),
                    icon: "menubar.rectangle",
                    accent: CockpitPalette.blueSoft,
                    language: model.appLanguage,
                    isOn: Binding(
                        get: { model.compactMenuBarEnabled },
                        set: { model.setCompactMenuBarEnabled($0) }
                    )
                )
            }
            .frame(maxWidth: 620)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? CockpitPalette.ice : CockpitPalette.separator)
                        .frame(width: index == page ? 24 : 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
            .accessibilityLabel(t("Step \(page + 1) of \(pageCount)", "Шаг \(page + 1) из \(pageCount)"))

            Spacer()

            if page > 0 {
                Button(t("Back", "Назад")) { move(to: page - 1) }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
            } else {
                Button(t("Skip", "Пропустить")) { finish() }
                    .buttonStyle(CockpitSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            Button(
                page == pageCount - 1
                    ? t("Open CodexAwake", "Открыть CodexAwake")
                    : t("Continue", "Продолжить")
            ) {
                page == pageCount - 1 ? finish() : move(to: page + 1)
            }
            .buttonStyle(CockpitPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 22)
    }

    private func move(to destination: Int) {
        guard (0..<pageCount).contains(destination) else { return }
        if reduceMotion {
            page = destination
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { page = destination }
        }
    }

    private func finish() {
        model.acknowledgeFirstRun()
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}

private struct OnboardingFact: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CockpitPalette.ice)
                .frame(width: 32, height: 32)
                .background(CockpitPalette.ice.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(CockpitPalette.muted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPanel(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPowerMode: View {
    let number: String
    let icon: String
    let title: String
    let detail: String
    let badge: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CockpitPalette.ice)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(CockpitPalette.ice)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(CockpitPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(badge)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CockpitPalette.ice)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(CockpitPalette.ice.opacity(0.09), in: Capsule())
        }
        .padding(17)
        .frame(minWidth: 190, maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(CockpitPanel(cornerRadius: 19))
        .accessibilityElement(children: .combine)
    }
}
