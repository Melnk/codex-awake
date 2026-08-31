import Foundation

public enum ClosedLidHelperCommandBuilder {
    public static func commandContents(scriptPath: String, title: String) -> String {
        let script = shellEscaped(scriptPath)
        return """
            #!/bin/zsh
            clear
            echo \(shellEscaped(title))
            echo "macOS will request an administrator password. The password is handled by sudo and is not visible to CodexAwake."
            echo
            /usr/bin/sudo \(script)
            result=$?
            echo
            if [[ $result -eq 0 ]]; then
                echo "Operation completed. Return to CodexAwake."
            else
                echo "Operation failed with status $result."
            fi
            echo "Press any key to close this window."
            read -k 1
            exit $result
            """
    }

    private static func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
