import Foundation

public struct ProtectionAutomationEngine: Sendable {
    public init() {}

    public func evaluate(
        rules: ProtectionAutomationRules,
        context: ProtectionAutomationContext,
        calendar: Calendar = .current
    ) -> ProtectionAutomationDecision {
        var blockers: [ProtectionAutomationBlocker] = []

        switch rules.trigger {
        case .codexRunning:
            if !context.codexIsRunning { blockers.append(.codexNotRunning) }
        case .activeTasks:
            if context.activeTaskCount == 0 { blockers.append(.noActiveTasks) }
        }

        if rules.automaticallyStopsAfterTasks, context.activeTaskCount == 0,
            !blockers.contains(.noActiveTasks)
        {
            blockers.append(.noActiveTasks)
        }
        if rules.requiresExternalPower, !context.isOnExternalPower {
            blockers.append(.externalPowerRequired)
        }
        if !rules.schedule.contains(context.date, calendar: calendar) {
            blockers.append(.outsideSchedule)
        }
        if !rules.selectedProjectPaths.isEmpty,
            !hasMatchingProject(
                activePaths: context.activeTaskProjectPaths,
                selectedPaths: rules.selectedProjectPaths
            )
        {
            blockers.append(.noSelectedProjectActive)
        }

        return ProtectionAutomationDecision(
            shouldProtect: blockers.isEmpty,
            blockers: blockers
        )
    }

    private func hasMatchingProject(activePaths: [String], selectedPaths: [String]) -> Bool {
        let selected = selectedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return activePaths.contains { activePath in
            let active = URL(fileURLWithPath: activePath).standardizedFileURL.path
            return selected.contains { selectedPath in
                active == selectedPath || active.hasPrefix(selectedPath + "/")
            }
        }
    }
}
