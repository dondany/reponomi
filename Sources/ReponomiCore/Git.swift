import Foundation

/// Finds command-line tools without relying on the shell.
enum Executable {
    /// The `PATH` first, then the usual install locations, because apps
    /// launched from Finder get a bare `PATH`.
    static var searchDirectories: [String] {
        let home = NSHomeDirectory()
        let path = ProcessInfo.processInfo.environment["PATH"]?.components(separatedBy: ":") ?? []
        return path + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "\(home)/.local/bin",
            "\(home)/.local/share/mise/shims",
            "\(home)/.asdf/shims",
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/usr/bin",
        ]
    }

    /// Relative `PATH` entries such as `.` are skipped: they would run
    /// whatever sits in the folder the app happened to be started from.
    static func find(_ name: String, in directories: [String] = searchDirectories) -> String? {
        directories.lazy
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }
}

public struct GitError: LocalizedError, Equatable {
    public let message: String

    public var errorDescription: String? { message }
}

public enum Git {
    /// Clones `url` into `destination`, which must not exist yet. Blocks
    /// until git exits; a clone that would need to ask for a password or a
    /// host key fails instead of waiting for an answer nobody can give.
    public static func clone(_ url: String, into destination: URL) throws {
        guard let git = Executable.find("git") else {
            throw GitError(message: "git isn’t installed.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        // "--" keeps a URL that starts with a dash from being read as an option.
        process.arguments = ["clone", "--quiet", "--", url, destination.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            throw GitError(message: lines.isEmpty ? "git exited with status \(process.terminationStatus)." : lines.suffix(2).joined(separator: " "))
        }
    }
}
