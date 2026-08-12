import CodexAwakeCore
import Darwin
import Foundation

func validatedClientHash(arguments: [String]) throws -> String {
    guard arguments.count == 3, arguments[1] == "--client-cdhash" else {
        throw ClosedLidDaemonError.invalidClientHash
    }
    let value = arguments[2].lowercased()
    let valid = value.count == 40 && value.allSatisfy(\.isHexDigit)
    guard valid else { throw ClosedLidDaemonError.invalidClientHash }
    return value
}

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
    let clientHash = try validatedClientHash(arguments: CommandLine.arguments)
    let store = LeaseStore()
    let service = HelperService(store: store)
    let delegate = ListenerDelegate(service: service)
    let listener = NSXPCListener(machServiceName: ClosedLidHelperConstants.machServiceName)
    listener.setConnectionCodeSigningRequirement("cdhash H\"\(clientHash)\"")
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
    FileHandle.standardError.write(
        Data("Closed-Lid helper failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
