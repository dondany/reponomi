import Foundation

/// The terminal apps that can be made to run a command in a new window.
public enum TerminalApp: String {
    case terminal = "com.apple.Terminal"
    case iTerm = "com.googlecode.iterm2"

    /// The terminal installed at `appPath`, if it is one of these.
    public init?(appPath: String) {
        guard let identifier = Bundle(path: appPath)?.bundleIdentifier else { return nil }
        self.init(rawValue: identifier)
    }
}

public struct TerminalError: LocalizedError, Equatable {
    public let message: String

    public var errorDescription: String? { message }
}

public enum TerminalCommand {
    /// Opens a new window of `terminal` in `directory` and runs `command`
    /// there, in the user's own shell. Blocks until the terminal has been
    /// told; the first time with iTerm, that includes macOS asking the user
    /// whether this app may control it.
    public static func run(_ command: String, in directory: URL, using terminal: TerminalApp, at appPath: String) throws {
        // The path ends up as keystrokes in a terminal, where a control
        // character is a key press (Ctrl-C, Return) that quoting can't stop.
        guard !directory.path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw TerminalError(message: "The folder’s path contains control characters, so it wasn’t opened in the terminal.")
        }
        switch terminal {
        case .terminal:
            // Terminal runs a .command file inside a normal login shell, and
            // needs no permission to do so.
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-\(UUID().uuidString).command")
            // Created private to the user from the start, not tightened afterwards.
            guard FileManager.default.createFile(
                atPath: file.path,
                contents: Data(script(directory: directory, command: command).utf8),
                attributes: [.posixPermissions: 0o700]
            ) else {
                throw TerminalError(message: "Couldn’t write the script for Terminal.")
            }
            try launch("/usr/bin/open", ["-a", appPath, file.path])
        case .iTerm:
            // iTerm asks for confirmation every time it is handed a script
            // file, so it is driven with AppleScript instead.
            do {
                try launch("/usr/bin/osascript", ["-e", iTermScript, line(directory: directory, command: command)])
            } catch let error as TerminalError where error.message.contains("-1743") {
                throw TerminalError(message: "Reponomi isn’t allowed to control iTerm. Allow it in System Settings › Privacy & Security › Automation.")
            }
        }
    }

    /// What is typed into a fresh shell: enter the folder, then run the
    /// command. The leading space keeps it out of most shells' history.
    static func line(directory: URL, command: String) -> String {
        " cd -- \(quote(directory.path)) && \(command)"
    }

    /// A self-deleting script that runs the command in the folder and then
    /// leaves a shell open there.
    static func script(directory: URL, command: String) -> String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        cd -- \(quote(directory.path)) || exit 1
        \(command)
        exec "${SHELL:-/bin/zsh}" -l

        """
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let iTermScript = """
    on run argv
        set wasRunning to application id "com.googlecode.iterm2" is running
        tell application id "com.googlecode.iterm2"
            activate
            if wasRunning then
                set theWindow to (create window with default profile)
            else
                -- A fresh launch opens a window of its own; use that one.
                repeat 50 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                end repeat
                if (count of windows) > 0 then
                    set theWindow to current window
                else
                    set theWindow to (create window with default profile)
                end if
            end if
            tell current session of theWindow to write text (item 1 of argv)
        end tell
    end run
    """

    private static func launch(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalError(message: reason.isEmpty ? "Couldn’t open the terminal." : reason)
        }
    }
}
