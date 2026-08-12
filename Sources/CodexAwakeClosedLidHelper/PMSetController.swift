import Foundation

final class PMSetController {
    private let executable = URL(fileURLWithPath: "/usr/bin/pmset")

    func captureDisableSleepSettings() throws -> [String: Int] {
        let output = try run(["-g", "custom"])
        var result: [String: Int] = [:]
        var profile = "all"

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            switch line {
            case "Battery Power:": profile = "battery"
            case "AC Power:": profile = "charger"
            case "UPS Power:": profile = "ups"
            default:
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count == 2, fields[0] == "disablesleep", let value = Int(fields[1]) {
                    result[profile] = value == 0 ? 0 : 1
                }
            }
        }
        return result.isEmpty ? ["all": 0] : result
    }

    func enableDisableSleep() throws {
        _ = try run(["-a", "disablesleep", "1"])
    }

    func restore(_ settings: [String: Int]) throws {
        _ = try run(["-a", "disablesleep", "0"])
        let flags = ["battery": "-b", "charger": "-c", "ups": "-u"]
        for (profile, value) in settings where value != 0 {
            if profile == "all" {
                _ = try run(["-a", "disablesleep", "1"])
            } else if let flag = flags[profile] {
                _ = try run([flag, "disablesleep", "1"])
            }
        }
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8) ?? "pmset failed"
            throw ClosedLidDaemonError.commandFailed(String(message.prefix(300)))
        }
        return String(data: stdout, encoding: .utf8) ?? ""
    }
}
