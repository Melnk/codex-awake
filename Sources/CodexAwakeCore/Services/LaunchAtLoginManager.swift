import ServiceManagement

public enum LaunchAtLoginState: String, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
public final class LaunchAtLoginManager {
    public init() {}

    public var isEnabled: Bool {
        state == .enabled
    }

    public var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
