import CodexAwakeCore
import Foundation

@main
struct ProtocolProbe {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: CodexAwakeProtocolProbe /path/to/socket\n".utf8))
            Foundation.exit(64)
        }
        let socketPath = CommandLine.arguments[1]
        let client = AppServerClient(
            endpoint: "unix://\(socketPath)",
            socketPath: socketPath,
            eventHandler: { _ in },
            disconnectHandler: { _ in }
        )
        do {
            try await client.connect()
            let result = try await client.reconcileStatuses()
            print("Handshake OK; loaded threads: \(result.loaded.count)")
            await client.disconnect()
        } catch {
            FileHandle.standardError.write(Data("Protocol probe failed: \(SafeDisplay.sanitizedError(error))\n".utf8))
            Foundation.exit(1)
        }
    }
}
