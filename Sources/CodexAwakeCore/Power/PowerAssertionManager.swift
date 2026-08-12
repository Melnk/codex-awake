import Foundation
import IOKit.pwr_mgt
import OSLog

public protocol PowerAssertionControlling: Sendable {
    func acquire() async throws
    func release() async
    func assertionIsHeld() async -> Bool
}

public actor PowerAssertionManager: PowerAssertionConfiguring {
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "Power")
    private var systemAssertionID: IOPMAssertionID?
    private var displayAssertionID: IOPMAssertionID?
    private let reason: String
    private var configuration: PowerAssertionConfiguration
    private var protectionRequested = false

    public init(
        reason: String = "CodexAwake: active Codex work or Codex desktop app",
        configuration: PowerAssertionConfiguration = .init()
    ) {
        self.reason = reason
        self.configuration = configuration
    }

    nonisolated public static var displayAssertionTypeName: String {
        kIOPMAssertPreventUserIdleDisplaySleep as String
    }

    nonisolated public static var systemAssertionTypeName: String {
        kIOPMAssertPreventUserIdleSystemSleep as String
    }

    public func acquire() throws {
        protectionRequested = true
        try reconcileAssertions()
    }

    public func setConfiguration(_ configuration: PowerAssertionConfiguration) throws {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        try reconcileAssertions()
    }

    public func release() {
        protectionRequested = false
        releaseAssertion(&displayAssertionID, label: "idle-display-sleep")
        releaseAssertion(&systemAssertionID, label: "idle-system-sleep")
    }

    public func assertionIsHeld() -> Bool {
        systemAssertionID != nil || displayAssertionID != nil
    }

    public func assertionSnapshot() -> PowerAssertionSnapshot {
        PowerAssertionSnapshot(
            protectionRequested: protectionRequested,
            systemSleepPrevented: systemAssertionID != nil,
            displaySleepPrevented: displayAssertionID != nil
        )
    }

    private func reconcileAssertions() throws {
        let needsSystem = protectionRequested && configuration.preventSystemSleep
        let needsDisplay = protectionRequested && configuration.preventDisplaySleep
        var newlyAcquiredSystem: IOPMAssertionID?
        var newlyAcquiredDisplay: IOPMAssertionID?

        do {
            if needsSystem, systemAssertionID == nil {
                newlyAcquiredSystem = try createAssertion(
                    type: kIOPMAssertPreventUserIdleSystemSleep as CFString
                )
            }
            if needsDisplay, displayAssertionID == nil {
                newlyAcquiredDisplay = try createAssertion(
                    type: kIOPMAssertPreventUserIdleDisplaySleep as CFString
                )
            }
        } catch {
            if let newlyAcquiredDisplay { IOPMAssertionRelease(newlyAcquiredDisplay) }
            if let newlyAcquiredSystem { IOPMAssertionRelease(newlyAcquiredSystem) }
            throw error
        }

        if let newlyAcquiredSystem {
            systemAssertionID = newlyAcquiredSystem
            logger.notice("Acquired the CodexAwake idle-system-sleep assertion")
        }
        if let newlyAcquiredDisplay {
            displayAssertionID = newlyAcquiredDisplay
            logger.notice("Acquired the CodexAwake idle-display-sleep assertion")
        }
        if !needsDisplay {
            releaseAssertion(&displayAssertionID, label: "idle-display-sleep")
        }
        if !needsSystem {
            releaseAssertion(&systemAssertionID, label: "idle-system-sleep")
        }
    }

    private func createAssertion(type: CFString) throws -> IOPMAssertionID {
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            throw CodexAwakeError.serverStartFailed("IOPMAssertionCreateWithName returned \(result)")
        }
        return newID
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID?, label: String) {
        guard let current = assertionID else { return }
        IOPMAssertionRelease(current)
        assertionID = nil
        logger.notice("Released the CodexAwake \(label, privacy: .public) assertion")
    }
}
