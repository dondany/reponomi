import Foundation

/// A place inside a repository on the web, e.g. its pull requests page.
public struct Location: Codable, Hashable {
    public var name: String
    /// Appended to the repository URL. `{branch}` expands to the default branch.
    public var path: String
    /// Short mnemonics that select this location, e.g. `p` or `pr`.
    public var keys: [String]
    /// True for the one location that isn't a web page: the clone on disk.
    public private(set) var isLocal = false

    private enum CodingKeys: String, CodingKey {
        case name, path, keys
    }

    public init(name: String, path: String, keys: [String] = []) {
        self.name = name
        self.path = path
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        keys = try container.decodeIfPresent([String].self, forKey: .keys) ?? []
    }

    /// The page's address, which is always an HTTPS URL on the repository's
    /// own host; anything else is refused rather than handed to the system.
    public func url(for repo: Repo) -> URL? {
        let branch = (repo.defaultBranch ?? "main").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "main"
        let expanded = path.replacingOccurrences(of: "{branch}", with: branch)
        guard repo.isWellFormed,
              let url = URL(string: repo.htmlURL + expanded),
              url.scheme == "https", url.host?.lowercased() == repo.host
        else { return nil }
        return url
    }
}

extension Location {
    public static let code = Location(name: "Code", path: "", keys: ["c", "code", "home"])

    /// Opens the repository's clone in the working directory, cloning it first if needed.
    public static let local: Location = {
        var location = Location(name: "Local folder", path: "", keys: ["l", "local", "clone"])
        location.isLocal = true
        return location
    }()

    public static let builtIn: [Location] = [
        code,
        local,
        Location(name: "Pull requests", path: "/pulls", keys: ["p", "pr", "prs", "pulls"]),
        Location(name: "Issues", path: "/issues", keys: ["i", "issues"]),
        Location(name: "Actions", path: "/actions", keys: ["a", "ci"]),
        Location(name: "Releases", path: "/releases", keys: ["r", "rel"]),
        Location(name: "Branches", path: "/branches", keys: ["b"]),
        Location(name: "Commits", path: "/commits", keys: ["co", "log"]),
        Location(name: "Tags", path: "/tags", keys: ["t"]),
        Location(name: "Settings", path: "/settings", keys: ["s"]),
        Location(name: "Wiki", path: "/wiki", keys: ["w"]),
        Location(name: "Discussions", path: "/discussions", keys: ["d"]),
        Location(name: "Projects", path: "/projects", keys: ["pj"]),
        Location(name: "Security", path: "/security", keys: ["se", "sec"]),
        Location(name: "Insights", path: "/pulse", keys: ["in", "pulse"]),
        Location(name: "My pull requests", path: "/pulls?q=is%3Apr+is%3Aopen+author%3A%40me", keys: ["mp", "my"]),
        Location(name: "New pull request", path: "/compare", keys: ["np", "compare"]),
        Location(name: "New issue", path: "/issues/new", keys: ["ni"]),
    ]

    /// Locations matching `query`, best first: an exact key wins, then a key
    /// prefix, then a fuzzy match on the name. Earlier entries win ties.
    public static func matching(_ query: String, in locations: [Location]) -> [Location] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return locations }

        let scored = locations.enumerated().compactMap { offset, location -> (score: Double, offset: Int, location: Location)? in
            let keys = location.keys.map { $0.lowercased() }
            if keys.contains(query) { return (1000, offset, location) }
            if keys.contains(where: { $0.hasPrefix(query) }) { return (500, offset, location) }
            guard let match = Fuzzy.match(query, in: location.name) else { return nil }
            return (match.score, offset, location)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.location)
    }
}
