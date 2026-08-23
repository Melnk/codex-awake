import Foundation
import IOKit.ps

public protocol PowerSourceProviding: Sendable {
    func isOnExternalPower() -> Bool
}

public struct SystemPowerSourceProvider: PowerSourceProviding {
    public init() {}

    public func isOnExternalPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let sourceReference = IOPSGetProvidingPowerSourceType(snapshot) else { return false }
        let source = sourceReference.takeUnretainedValue() as String
        return source == kIOPSACPowerValue || source == "UPS Power"
    }
}
