import CodexAwakeCore
import Darwin
import Foundation
import OSLog

private let logger = Logger(
    subsystem: ClosedLidHelperConstants.label,
    category: "Bootstrap"
)

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("Closed-Lid helper must run as root\n".utf8))
    exit(EXIT_FAILURE)
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--recover" {
    do {
        try LeaseStore.recoverPersistedState()
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Recovery failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

do {
    let clientRequirement = try ClosedLidClientAuthorization.codeSigningRequirement(
        arguments: CommandLine.arguments
    )
    let store = LeaseStore()
    let service = HelperService(store: store)
    let delegate = ListenerDelegate(service: service)
    let listener = NSXPCListener(machServiceName: ClosedLidHelperConstants.machServiceName)
    listener.setConnectionCodeSigningRequirement(clientRequirement)
    listener.delegate = delegate

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler {
        store.shutdownAndRestore()
        exit(EXIT_SUCCESS)
    }
    termination.resume()

    listener.activate()
    RunLoop.current.run()
} catch {
    logger.fault("Closed-Lid helper failed: \(error.localizedDescription, privacy: .public)")
    FileHandle.standardError.write(
        Data("Closed-Lid helper failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
