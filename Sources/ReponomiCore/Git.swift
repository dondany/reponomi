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

    /// The branch checked out in the clone at `directory`, or its commit when
    /// HEAD is detached. Read from `.git/HEAD` rather than by running git,
    /// which a clone's own config could make run other programs.
    public static func checkedOutRef(in directory: URL) -> String? {
        let head = directory.appendingPathComponent(".git/HEAD")
        guard let values = try? head.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= 4_096,
              let text = try? String(contentsOf: head, encoding: .utf8)
        else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        if line.hasPrefix(prefix) {
            let branch = String(line.dropFirst(prefix.count))
            return isSafeRef(branch) ? branch : nil
        }
        return GitHubClient.isCommitHash(line) ? line : nil
    }

    /// A branch name that is safe to put in a URL path: what git itself
    /// allows, minus anything that could step out of the path (`..`, empty
    /// segments) or end it (`?`, `#`), and minus spaces and control characters.
    public static func isSafeRef(_ ref: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\#%").union(.controlCharacters).union(.whitespacesAndNewlines)
        return !ref.isEmpty && ref.utf8.count <= 255
            && ref.unicodeScalars.allSatisfy { !forbidden.contains($0) }
            && !ref.contains("@{") && !ref.hasSuffix(".lock")
            && ref.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") }
    }
}
