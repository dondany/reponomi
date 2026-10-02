import Foundation

public struct Repo: Codable, Hashable {
    /// GitHub's numeric id, unique only within one host; `htmlURL` is unique across hosts.
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: String
    public let htmlURL: String
    public let description: String?
    public let isPrivate: Bool
    public let isArchived: Bool
    public let isFork: Bool
    public let pushedAt: Date?
    public let defaultBranch: String?

    public init(
        id: Int,
        name: String,
        owner: String,
        htmlURL: String? = nil,
        description: String? = nil,
        isPrivate: Bool = false,
        isArchived: Bool = false,
        isFork: Bool = false,
        pushedAt: Date? = nil,
        defaultBranch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = "\(owner)/\(name)"
        self.owner = owner
        self.htmlURL = htmlURL ?? "https://github.com/\(owner)/\(name)"
        self.description = description
        self.isPrivate = isPrivate
        self.isArchived = isArchived
        self.isFork = isFork
        self.pushedAt = pushedAt
        self.defaultBranch = defaultBranch
    }

    /// The hostname the repository lives on, e.g. `github.com`.
    public var host: String {
        URL(string: htmlURL)?.host?.lowercased() ?? ""
    }

    /// GitHub allows only these characters in owner and repository names.
    /// Anything else, such as a slash or `..`, could steer a URL or a clone
    /// somewhere it shouldn't go.
    public static func isSafeName(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return !name.isEmpty && name != "." && name != ".." && name.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Whether this is exactly what the app builds from an API response: a
    /// plain `https://host/owner/name`. Anything read back from disk is held
    /// to that before it is opened or cloned.
    public var isWellFormed: Bool {
        Self.isSafeName(owner) && Self.isSafeName(name) && Config.isValidHost(host)
            && fullName == "\(owner)/\(name)" && htmlURL == "https://\(host)/\(fullName)"
    }

    /// Identifies the repository across hosts, e.g. `github.com/acme/api`.
    public var key: String {
        "\(host)/\(fullName)".lowercased()
    }
}
