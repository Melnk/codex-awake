import Foundation

public enum ProtectionTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    case codexRunning
    case activeTasks

    public var id: String { rawValue }
}

public enum ProtectionProfileID: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case nightTask
    case closedLid
    case presentation

    public var id: String { rawValue }
}

public enum AutomationWeekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var id: Int { rawValue }

    public static let weekdays: Set<Self> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let everyDay: Set<Self> = Set(allCases)
}

public struct ProtectionSchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var startMinute: Int
    public var endMinute: Int
    public var weekdays: Set<AutomationWeekday>

    public init(
        isEnabled: Bool = false,
        startMinute: Int = 9 * 60,
        endMinute: Int = 19 * 60,
        weekdays: Set<AutomationWeekday> = AutomationWeekday.weekdays
    ) {
        self.isEnabled = isEnabled
        self.startMinute = Self.validMinute(startMinute)
        self.endMinute = Self.validMinute(endMinute)
        self.weekdays = weekdays
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return true }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard
            let weekdayValue = components.weekday,
            let weekday = AutomationWeekday(rawValue: weekdayValue),
            let hour = components.hour,
            let minute = components.minute
        else { return false }

        let currentMinute = hour * 60 + minute
        if startMinute == endMinute {
            return weekdays.contains(weekday)
        }
        if startMinute < endMinute {
            return weekdays.contains(weekday)
                && currentMinute >= startMinute
                && currentMinute < endMinute
        }

        if currentMinute >= startMinute {
            return weekdays.contains(weekday)
        }
        guard currentMinute < endMinute else { return false }
        return weekdays.contains(Self.previous(weekday))
    }

    private static func validMinute(_ value: Int) -> Int {
        min(max(value, 0), 23 * 60 + 59)
    }

    private static func previous(_ weekday: AutomationWeekday) -> AutomationWeekday {
        AutomationWeekday(rawValue: weekday.rawValue == 1 ? 7 : weekday.rawValue - 1) ?? .sunday
    }
}

public struct ProtectionAutomationRules: Codable, Equatable, Sendable {
    public var trigger: ProtectionTrigger
    public var requiresExternalPower: Bool
    public var automaticallyStopsAfterTasks: Bool
    public var schedule: ProtectionSchedule
    public var selectedProjectPaths: [String]

    public init(
        trigger: ProtectionTrigger = .codexRunning,
        requiresExternalPower: Bool = false,
        automaticallyStopsAfterTasks: Bool = false,
        schedule: ProtectionSchedule = .init(),
        selectedProjectPaths: [String] = []
    ) {
        self.trigger = trigger
        self.requiresExternalPower = requiresExternalPower
        self.automaticallyStopsAfterTasks = automaticallyStopsAfterTasks
        self.schedule = schedule
        self.selectedProjectPaths = Self.normalizedPaths(selectedProjectPaths)
    }

    public mutating func normalizeProjectPaths() {
        selectedProjectPaths = Self.normalizedPaths(selectedProjectPaths)
    }

    private static func normalizedPaths(_ paths: [String]) -> [String] {
        Array(
            Set(
                paths.compactMap { path -> String? in
                    let value = URL(fileURLWithPath: path).standardizedFileURL.path
                    return value == "/" || value.isEmpty ? nil : value
                }
            )
        ).sorted()
    }
}

public struct ProtectionProfile: Equatable, Sendable {
    public let id: ProtectionProfileID
    public let rules: ProtectionAutomationRules
    public let power: PowerAssertionConfiguration
    public let closedLidEnabled: Bool

    public init(
        id: ProtectionProfileID,
        rules: ProtectionAutomationRules,
        power: PowerAssertionConfiguration,
        closedLidEnabled: Bool
    ) {
        self.id = id
        self.rules = rules
        self.power = power
        self.closedLidEnabled = closedLidEnabled
    }

    public static func preset(_ id: ProtectionProfileID) -> Self {
        switch id {
        case .work:
            Self(
                id: id,
                rules: .init(trigger: .activeTasks, automaticallyStopsAfterTasks: true),
                power: .init(preventSystemSleep: true, preventDisplaySleep: true),
                closedLidEnabled: false
            )
        case .nightTask:
            Self(
                id: id,
                rules: .init(
                    trigger: .codexRunning,
                    requiresExternalPower: true,
                    automaticallyStopsAfterTasks: false,
                    schedule: .init(
                        isEnabled: true,
                        startMinute: 22 * 60,
                        endMinute: 7 * 60,
                        weekdays: AutomationWeekday.everyDay
                    )
                ),
                power: .init(preventSystemSleep: true, preventDisplaySleep: false),
                closedLidEnabled: false
            )
        case .closedLid:
            Self(
                id: id,
                rules: .init(
                    trigger: .codexRunning,
                    automaticallyStopsAfterTasks: false
                ),
                power: .init(preventSystemSleep: true, preventDisplaySleep: false),
                closedLidEnabled: true
            )
        case .presentation:
            Self(
                id: id,
                rules: .init(trigger: .codexRunning),
                power: .init(preventSystemSleep: true, preventDisplaySleep: true),
                closedLidEnabled: false
            )
        }
    }
}

public struct ProtectionAutomationContext: Equatable, Sendable {
    public var codexIsRunning: Bool
    public var activeTaskCount: Int
    public var activeTaskProjectPaths: [String]
    public var isOnExternalPower: Bool
    public var date: Date

    public init(
        codexIsRunning: Bool,
        activeTaskCount: Int? = nil,
        activeTaskProjectPaths: [String],
        isOnExternalPower: Bool,
        date: Date = Date()
    ) {
        self.codexIsRunning = codexIsRunning
        self.activeTaskCount = max(0, activeTaskCount ?? activeTaskProjectPaths.count)
        self.activeTaskProjectPaths = activeTaskProjectPaths
        self.isOnExternalPower = isOnExternalPower
        self.date = date
    }
}

public enum ProtectionAutomationBlocker: String, Codable, Equatable, Sendable {
    case codexNotRunning
    case noActiveTasks
    case externalPowerRequired
    case outsideSchedule
    case noSelectedProjectActive
}

public struct ProtectionAutomationDecision: Equatable, Sendable {
    public var shouldProtect: Bool
    public var blockers: [ProtectionAutomationBlocker]

    public init(shouldProtect: Bool, blockers: [ProtectionAutomationBlocker] = []) {
        self.shouldProtect = shouldProtect
        self.blockers = blockers
    }
}
