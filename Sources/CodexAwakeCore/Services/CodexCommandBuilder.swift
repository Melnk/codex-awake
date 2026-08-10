import Foundation

public enum CodexCommandBuilder {
    public static func command(binaryPath: String, endpoint: String) -> String {
        "\(shellQuote(binaryPath)) --remote \(shellQuote(endpoint))"
    }

    public static func helperContents(binaryPath: String, endpoint: String) -> String {
        """
        #!/bin/zsh
        exec \(command(binaryPath: binaryPath, endpoint: endpoint))
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
