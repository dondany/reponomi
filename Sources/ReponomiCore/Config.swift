import Foundation

/// A global shortcut as Carbon expects it: a virtual key code plus a Carbon
/// modifier mask. `display` is the human-readable form, e.g. `⌃⌥R`.
public struct HotkeySpec: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// ⌃⌥R
    public static let `default` = HotkeySpec(keyCode: 15, modifiers: 0x1800, display: "⌃⌥R")
}

/// Where the app gets its GitHub credentials from.
public enum AuthMethod: String, Codable {
    /// A token saved in Settings; none means anonymous requests.
    case token
    /// Whatever account the GitHub CLI is logged in with.
    case githubCLI = "gh"
}

public enum CloneProtocol: String, Codable {
    case ssh, https
}

/// One GitHub host, how to sign in to it, and which repositories to list from it.
public struct Account: Codable, Equatable {
    /// `github.com`, or the hostname of a GitHub Enterprise instance.
    public var host = "github.com"
    public var auth = AuthMethod.token
    /// Organizations or users whose repositories are listed.
    public var owners: [String] = []
    /// Also list every repository the signed-in user can access.
    public var includeMyRepos = false
    /// The folder this host's repositories are cloned into; `~` is allowed.
    public var workingDirectory: String?
    public var cloneProtocol = CloneProtocol.ssh

    public init(
        host: String = "github.com",
        auth: AuthMethod = .token,
        owners: [String] = [],
        includeMyRepos: Bool = false,
        workingDirectory: String? = nil,
        cloneProtocol: CloneProtocol = .ssh
    ) {
        self.host = host
        self.auth = auth
        self.owners = owners
        self.includeMyRepos = includeMyRepos
        self.workingDirectory = workingDirectory
        self.cloneProtocol = cloneProtocol
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Account()
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? defaults.host
        auth = try container.decodeIfPresent(AuthMethod.self, forKey: .auth) ?? defaults.auth
        owners = try container.decodeIfPresent([String].self, forKey: .owners) ?? defaults.owners
        includeMyRepos = try container.decodeIfPresent(Bool.self, forKey: .includeMyRepos) ?? defaults.includeMyRepos
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        cloneProtocol = try container.decodeIfPresent(CloneProtocol.self, forKey: .cloneProtocol) ?? defaults.cloneProtocol
    }

    public var hasSources: Bool { !owners.isEmpty || includeMyRepos }

    public var workingDirectoryURL: URL? {
        guard let path = workingDirectory?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// What to hand `git clone` for `repo`.
    public func cloneURL(for repo: Repo) -> String {
        switch cloneProtocol {
        case .ssh: return "git@\(repo.host):\(repo.fullName).git"
        case .https: return "\(repo.htmlURL).git"
        }
    }
}

public struct Config: Codable, Equatable {
    /// At most one account per host.
    public var accounts = [Account()]
    public var includeArchived = false
    public var includeForks = true
    public var refreshMinutes = 60
    public var hotkey = HotkeySpec.default
    /// Extra locations, listed (and matched) ahead of the built-in ones.
    public var customLocations: [Location] = []
    /// Keys (`Repo.key`) of repositories hidden from the search.
    public var ignored: [String] = []
    /// Path of the app that local folders are opened with; nil means Finder.
    public var localApp: String?
    /// A command to run in the folder, e.g. `lazygit`, when `localApp` is a
    /// terminal that `TerminalApp` knows how to drive.
    public var localCommand: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        // Before several accounts were supported, the fields of the only
        // account sat at the top level.
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? [Account(from: decoder)]
        includeArchived = try container.decodeIfPresent(Bool.self, forKey: .includeArchived) ?? defaults.includeArchived
        includeForks = try container.decodeIfPresent(Bool.self, forKey: .includeForks) ?? defaults.includeForks
        refreshMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? defaults.refreshMinutes
        hotkey = try container.decodeIfPresent(HotkeySpec.self, forKey: .hotkey) ?? defaults.hotkey
        customLocations = try container.decodeIfPresent([Location].self, forKey: .customLocations) ?? defaults.customLocations
        ignored = try container.decodeIfPresent([String].self, forKey: .ignored) ?? defaults.ignored
        localApp = try container.decodeIfPresent(String.self, forKey: .localApp)
        localCommand = try container.decodeIfPresent(String.self, forKey: .localCommand)
    }

    public var hasSources: Bool { accounts.contains(where: \.hasSources) }

    /// The account `repo` was listed from.
    public func account(for repo: Repo) -> Account? {
        accounts.first { $0.host == repo.host }
    }

    /// Whether repositories can come from more than one host, in which case
    /// the list says which host each one is on.
    public var spansHosts: Bool { accounts.filter(\.hasSources).count > 1 }

    /// The list to show after a refresh. Hosts that failed keep the
    /// repositories they had before, so being off the VPN doesn't empty the
    /// list of an internal server.
    public func merge(fetched: [Repo], previous: [Repo], failedHosts: Set<String>) -> [Repo] {
        var seen = Set<String>()
        return (fetched + previous.filter { failedHosts.contains($0.host) }).filter { repo in
            (includeArchived || !repo.isArchived)
                && (includeForks || !repo.isFork)
                && seen.insert(repo.htmlURL).inserted
        }
    }

    public var locations: [Location] { customLocations + Location.builtIn }

    /// Splits user input such as `my-org, @someone other-org` into owner names.
    public static func parseOwners(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Whether `host` is a bare hostname. The token is sent to it and URLs
    /// are built from it, so `user@host`, ports, paths and the like — which
    /// can make a URL go somewhere other than it appears to — are refused.
    public static func isValidHost(_ host: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return host.count <= 253
            && host.unicodeScalars.allSatisfy(allowed.contains)
            && labels.allSatisfy { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }

    /// Reduces user input such as `https://github.example.com/` to a hostname.
    public static func normalizeHost(_ text: String) -> String {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        host = String(host.prefix { $0 != "/" })
        return host.isEmpty ? "github.com" : host
    }
}
