import Foundation

public struct CodexBinaryInfo: Equatable, Sendable {
    public let path: String
    public let version: String

    public init(path: String, version: String) {
        self.path = path
        self.version = version
    }
}

public protocol CodexBinaryLocating: Sendable {
    func locate() async throws -> CodexBinaryInfo
}

public struct CodexBinaryLocator: CodexBinaryLocating, @unchecked Sendable {
    public static let userDefaultsKey = "CodexBinaryPath"
    private let fileManager: FileManager
    private let defaults: UserDefaults

    public init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    public func locate() async throws -> CodexBinaryInfo {
        var candidates: [String] = []
        if let custom = defaults.string(forKey: Self.userDefaultsKey), !custom.isEmpty {
            candidates.append(custom)
        }
        candidates += Self.bundledCodexCandidates(homeDirectory: fileManager.homeDirectoryForCurrentUser)
        if let shellPath = try? await Self.capture(
            executable: "/bin/zsh",
            arguments: ["-lic", "command -v codex"],
            timeout: .seconds(5)
        ).trimmingCharacters(in: .whitespacesAndNewlines), !shellPath.isEmpty {
            candidates.append(shellPath)
        }
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/bin/codex").path,
        ]

        var lastCompatibilityError: Error?
        for candidate in candidates.uniqued() where fileManager.isExecutableFile(atPath: candidate) {
            do {
                let version = try await Self.capture(
                    executable: candidate, arguments: ["--version"], timeout: .seconds(5)
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                let mainHelp = try await Self.capture(
                    executable: candidate, arguments: ["--help"], timeout: .seconds(5))
                let help = try await Self.capture(
                    executable: candidate, arguments: ["app-server", "--help"], timeout: .seconds(5))
                guard Self.isCompatible(mainHelp: mainHelp, appServerHelp: help) else {
                    lastCompatibilityError = CodexAwakeError.incompatibleCodex(
                        "help does not advertise both `--remote` and Unix socket App Server listening"
                    )
                    continue
                }
                return CodexBinaryInfo(path: candidate, version: version)
            } catch {
                lastCompatibilityError = error
            }
        }
        if let lastCompatibilityError { throw lastCompatibilityError }
        throw CodexAwakeError.codexNotFound
    }

    public static func bundledCodexCandidates(homeDirectory: URL) -> [String] {
        let relativePaths = [
            "ChatGPT.app/Contents/Resources/codex",
            "Codex.app/Contents/Resources/codex",
        ]
        return relativePaths.map { "/Applications/\($0)" }
            + relativePaths.map { homeDirectory.appendingPathComponent("Applications/\($0)").path }
    }

    public func saveUserSelectedPath(_ path: String) throws {
        guard fileManager.isExecutableFile(atPath: path) else {
            throw CodexAwakeError.codexNotExecutable(path)
        }
        defaults.set(path, forKey: Self.userDefaultsKey)
    }

    public static func isCompatible(appServerHelp: String) -> Bool {
        appServerHelp.contains("--listen") && appServerHelp.contains("unix://")
    }

    public static func isCompatible(mainHelp: String, appServerHelp: String) -> Bool {
        mainHelp.contains("--remote") && isCompatible(appServerHelp: appServerHelp)
    }

    private static func capture(executable: String, arguments: [String], timeout: Duration) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while process.isRunning, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw CodexAwakeError.timeout(arguments.joined(separator: " "))
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let detail =
                    String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "exit \(process.terminationStatus)"
                throw CodexAwakeError.incompatibleCodex(String(detail.prefix(300)))
            }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
