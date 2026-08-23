import CodexAwakeCore
import SwiftUI

struct AutomationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("AUTOMATION 2.0", "АВТОМАТИЗАЦИЯ 2.0"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(CockpitPalette.muted)
                    Text(t("Protection rules", "Правила защиты"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                Spacer()
                automationStatus
            }

            profiles
            triggerPicker
            ruleToggles

            if model.automationRules.schedule.isEnabled {
                scheduleEditor
            }

            projectFilter
            statistics

            Text(
                t(
                    "Shortcuts: ⌘⌥A toggles protection; ⌘⌥1–4 applies a profile. The same actions are available in Apple Shortcuts and AppleScript.",
                    "Горячие клавиши: ⌘⌥A включает защиту; ⌘⌥1–4 применяют профиль. Эти действия также доступны в «Командах» Apple и AppleScript."
                )
            )
            .font(.system(size: 9))
            .foregroundStyle(CockpitPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CockpitPalette.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CockpitPalette.separator.opacity(0.58)))
    }

    private var automationStatus: some View {
        Label(
            model.automationDecision.shouldProtect
                ? t("READY", "ГОТОВО")
                : blockerLabel,
            systemImage: model.automationDecision.shouldProtect ? "checkmark.circle.fill" : "pause.circle"
        )
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .foregroundStyle(model.automationDecision.shouldProtect ? CockpitPalette.ice : CockpitPalette.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            (model.automationDecision.shouldProtect ? CockpitPalette.ice : CockpitPalette.muted).opacity(0.09),
            in: Capsule()
        )
    }

    private var profiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
            ForEach(ProtectionProfileID.allCases) { profile in
                Button {
                    model.applyProtectionProfile(profile)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: profileSymbol(profile))
                            .frame(width: 15)
                        Text(profileTitle(profile))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if model.selectedProtectionProfile == profile {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        model.selectedProtectionProfile == profile ? Color.white : CockpitPalette.silver
                    )
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        model.selectedProtectionProfile == profile
                            ? CockpitPalette.ice : CockpitPalette.canvas.opacity(0.58),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    t("Apply \(profileTitle(profile)) profile", "Применить профиль «\(profileTitle(profile))»")
                )
            }
        }
    }

    private var triggerPicker: some View {
        Picker(
            t("Protect", "Включать защиту"),
            selection: Binding(
                get: { model.automationRules.trigger },
                set: { model.setAutomationTrigger($0) }
            )
        ) {
            Text(t("While Codex runs", "Пока запущен Codex"))
                .tag(ProtectionTrigger.codexRunning)
            Text(t("For active tasks", "Для активных задач"))
                .tag(ProtectionTrigger.activeTasks)
        }
        .pickerStyle(.segmented)
        .font(.system(size: 10))
    }

    private var ruleToggles: some View {
        VStack(spacing: 7) {
            automationToggle(
                title: t("Only on external power", "Только от зарядки"),
                symbol: model.isOnExternalPower ? "powerplug.fill" : "powerplug",
                isOn: model.automationRules.requiresExternalPower,
                action: model.setRequiresExternalPower
            )
            automationToggle(
                title: t("Use schedule", "Работать по расписанию"),
                symbol: "calendar.badge.clock",
                isOn: model.automationRules.schedule.isEnabled,
                action: model.setScheduleEnabled
            )
            automationToggle(
                title: t("Stop after all tasks finish", "Выключать после завершения задач"),
                symbol: "checkmark.circle",
                isOn: model.automationRules.automaticallyStopsAfterTasks,
                action: model.setAutomaticallyStopsAfterTasks
            )
        }
    }

    private func automationToggle(
        title: String,
        symbol: String,
        isOn: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            action(!isOn)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(isOn ? CockpitPalette.ice : CockpitPalette.muted)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                PremiumSwitchIndicator(isOn: isOn)
                    .accessibilityHidden(true)
            }
            .padding(9)
            .contentShape(Rectangle())
            .background(CockpitPalette.canvas.opacity(0.46), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? t("On", "Включено") : t("Off", "Выключено"))
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DatePicker(
                    t("From", "С"),
                    selection: scheduleDateBinding(start: true),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    t("To", "До"),
                    selection: scheduleDateBinding(start: false),
                    displayedComponents: .hourAndMinute
                )
            }
            .font(.system(size: 9))

            HStack(spacing: 4) {
                ForEach(AutomationWeekday.allCases) { weekday in
                    let selected = model.automationRules.schedule.weekdays.contains(weekday)
                    Button {
                        model.toggleScheduleWeekday(weekday)
                    } label: {
                        Text(weekdayTitle(weekday))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 25)
                            .foregroundStyle(selected ? Color.white : CockpitPalette.muted)
                            .background(
                                selected ? CockpitPalette.ice : CockpitPalette.canvas.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .background(CockpitPalette.canvas.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    }

    private var projectFilter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(t("PROJECT FILTER", "ФИЛЬТР ПРОЕКТОВ"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(CockpitPalette.muted)
                Spacer()
                Button {
                    model.addAutomationProjects()
                } label: {
                    Label(t("Add", "Добавить"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9, weight: .semibold))
            }

            if model.automationRules.selectedProjectPaths.isEmpty {
                Text(t("All tracked projects", "Все отслеживаемые проекты"))
                    .font(.system(size: 10))
                    .foregroundStyle(CockpitPalette.muted)
            } else {
                ForEach(model.automationRules.selectedProjectPaths, id: \.self) { path in
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .foregroundStyle(CockpitPalette.ice)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.removeAutomationProject(path)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("Remove project", "Удалить проект"))
                    }
                    .font(.system(size: 9, design: .rounded))
                    .help(path)
                }
            }
        }
        .padding(9)
        .background(CockpitPalette.canvas.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statistics: some View {
        HStack(spacing: 8) {
            statistic(
                value: formattedDuration(model.protectionStatistics.protectedSeconds),
                label: t("PROTECTED", "ПОД ЗАЩИТОЙ"),
                symbol: "timer"
            )
            statistic(
                value: "\(model.protectionStatistics.sleepPreventionSessions)",
                label: t("SESSIONS", "СЕССИЙ ЗАЩИТЫ"),
                symbol: "moon.zzz.fill"
            )
        }
    }

    private func statistic(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(CockpitPalette.violetSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(CockpitPalette.muted)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPalette.canvas.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    }

    private func scheduleDateBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minute =
                    start
                    ? model.automationRules.schedule.startMinute
                    : model.automationRules.schedule.endMinute
                return Calendar.current.date(
                    bySettingHour: minute / 60,
                    minute: minute % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                if start {
                    model.setScheduleStartMinute(minute)
                } else {
                    model.setScheduleEndMinute(minute)
                }
            }
        )
    }

    private var blockerLabel: String {
        guard let blocker = model.automationDecision.blockers.first else {
            return t("PAUSED", "ПАУЗА")
        }
        switch blocker {
        case .codexNotRunning: return t("CODEX OFF", "CODEX ВЫКЛ")
        case .noActiveTasks: return t("NO TASKS", "НЕТ ЗАДАЧ")
        case .externalPowerRequired: return t("NO POWER", "НЕТ ЗАРЯДКИ")
        case .outsideSchedule: return t("SCHEDULE", "РАСПИСАНИЕ")
        case .noSelectedProjectActive: return t("PROJECT", "ПРОЕКТ")
        }
    }

    private func profileTitle(_ profile: ProtectionProfileID) -> String {
        switch profile {
        case .work: t("Work", "Работа")
        case .nightTask: t("Night task", "Ночная задача")
        case .closedLid: t("Closed lid", "Закрытая крышка")
        case .presentation: t("Presentation", "Презентация")
        }
    }

    private func profileSymbol(_ profile: ProtectionProfileID) -> String {
        switch profile {
        case .work: "briefcase.fill"
        case .nightTask: "moon.stars.fill"
        case .closedLid: "lock.display"
        case .presentation: "rectangle.inset.filled.and.person.filled"
        }
    }

    private func weekdayTitle(_ weekday: AutomationWeekday) -> String {
        let english = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let russian = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        return model.appLanguage == .russian
            ? russian[weekday.rawValue - 1]
            : english[weekday.rawValue - 1]
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "\(totalMinutes)m"
    }

    private func t(_ english: String, _ russian: String) -> String {
        model.appLanguage.text(english, russian)
    }
}
