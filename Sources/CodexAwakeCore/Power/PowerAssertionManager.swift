import Foundation
import IOKit.pwr_mgt
import OSLog

public protocol PowerAssertionControlling: Sendable {
    func acquire() async throws
    func release() async
    func assertionIsHeld() async -> Bool
}

public actor PowerAssertionManager: PowerAssertionControlling {
    private let logger = Logger(subsystem: "com.melnikoleg.CodexAwake", category: "Power")
    private var assertionID: IOPMAssertionID?
    private let reason: String

    public init(reason: String = "CodexAwake: active Codex work or Codex desktop app") {
        self.reason = reason
    }

    public func acquire() throws {
        guard assertionID == nil else { return }
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            throw CodexAwakeError.serverStartFailed("IOPMAssertionCreateWithName returned \(result)")
        }
        assertionID = newID
        logger.notice("Acquired the CodexAwake idle-system-sleep assertion")
    }

    public func release() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
        logger.notice("Released the CodexAwake idle-system-sleep assertion")
    }

    public func assertionIsHeld() -> Bool {
        assertionID != nil
    }
}
