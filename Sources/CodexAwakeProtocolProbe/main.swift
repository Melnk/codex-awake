import CodexAwakeCore
import Foundation

@main
struct ProtocolProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--scan-desktop" {
            let sessions = CodexDesktopRolloutScanner().activeSessions(
                in: URL(fileURLWithPath: arguments[1], isDirectory: true)
            )
            print("Active Desktop rollouts: \(sessions.count)")
            for session in sessions {
                print(SafeDisplay.abbreviated(session.id))
            }
            return
        }
        guard arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--start-thread") else {
            FileHandle.standardError.write(
                Data(
                    "usage: CodexAwakeProtocolProbe /path/to/socket [--start-thread /workspace] | --scan-desktop /sessions/root\n"
                        .utf8
                ))
            Foundation.exit(64)
        }
        let socketPath = arguments[0]
        let client = AppServerClient(
            endpoint: "unix://\(socketPath)",
            socketPath: socketPath,
            eventHandler: { _ in },
            disconnectHandler: { _ in }
        )
        do {
            try await client.connect()
            let result = try await client.reconcileStatuses()
            let models = try await client.listModels()
            print(
                "Handshake OK; loaded threads: \(result.loaded.count); metadata records: \(result.summaries.count); picker models: \(models.count)"
            )
            if arguments.count == 3 {
                let threadID = try await client.startThread(cwd: arguments[2])
                print("Thread start OK: \(SafeDisplay.abbreviated(threadID))")
            }
            await client.disconnect()
        } catch {
            FileHandle.standardError.write(Data("Protocol probe failed: \(SafeDisplay.sanitizedError(error))\n".utf8))
            Foundation.exit(1)
        }
    }
}
