import Foundation

public enum GitHubCLIError: LocalizedError, Equatable {
    case notInstalled
    case notLoggedIn(host: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The GitHub CLI (gh) isn’t installed. Install it with “brew install gh”, or sign in with an access token instead."
        case .notLoggedIn(let host):
            let command = host == "github.com" ? "gh auth login" : "gh auth login --hostname \(host)"
            return "The GitHub CLI isn’t logged in to \(host). Run “\(command)” in a terminal."
        }
    }
}

/// The `gh` command-line tool, whose login the app can borrow instead of
/// keeping a token of its own.
public struct GitHubCLI: Equatable {
    public let path: String

    public static func locate() -> GitHubCLI? {
        Executable.find("gh").map(GitHubCLI.init(path:))
    }

    static func locate(in directories: [String]) -> GitHubCLI? {
        Executable.find("gh", in: directories).map(GitHubCLI.init(path:))
    }

    /// The token `gh` is logged in with on `host`. Blocks while `gh` runs.
    public static func token(for host: String) throws -> String {
        guard let cli = locate() else { throw GitHubCLIError.notInstalled }
        return try cli.token(for: host)
    }

    public func token(for host: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["auth", "token", "--hostname", host]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GitHubCLIError.notInstalled
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !token.isEmpty else {
            throw GitHubCLIError.notLoggedIn(host: host)
        }
        return token
    }
}
