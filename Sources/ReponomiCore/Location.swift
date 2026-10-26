import Foundation

/// A place inside a repository on the web, e.g. its pull requests page.
public struct Location: Codable, Hashable {
    public var name: String
    /// Appended to the repository URL. `{branch}` expands to the default
    /// branch, `{sha}` to the latest commit on the checked-out branch (see
    /// `resolve`).
    public var path: String
    /// Short mnemonics that select this location, e.g. `p` or `pr`.
    public var keys: [String]
    /// True for the one location that isn't a web page: the clone on disk.
    public private(set) var isLocal = false
    /// Where a built-in location goes when the latest commit can't be looked
    /// up, for example because the token isn't allowed to read code.
    public private(set) var fallbackPath: String?
    /// True for the built-in location that opens a CI build: the link of the
    /// commit's most relevant check, when `CICheck.openableURL` allows it.
    public private(set) var opensBuild = false

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

    /// Whether opening this location needs the latest commit looked up first.
    public var needsHeadCommit: Bool {
        path.contains("{sha}")
    }

    /// The page's address, which is always an HTTPS URL on the repository's
    /// own host; anything else is refused rather than handed to the system.
    /// Nil when the path has `{sha}` and `headCommit` isn't a commit hash.
    public func url(for repo: Repo, headCommit: String? = nil) -> URL? {
        let branch = (repo.defaultBranch ?? "main").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "main"
        var expanded = path.replacingOccurrences(of: "{branch}", with: branch)
        if needsHeadCommit {
            guard let headCommit, GitHubClient.isCommitHash(headCommit) else { return nil }
            expanded = expanded.replacingOccurrences(of: "{sha}", with: headCommit)
        }
        guard repo.isWellFormed,
              let url = URL(string: repo.htmlURL + expanded),
              url.scheme == "https", url.host?.lowercased() == repo.host
        else { return nil }
        return url
    }

    /// Where to go. A location with `{sha}` asks `lookup` for the latest
    /// commit on `ref` (a branch, usually the one checked out), else on the
    /// default branch, else goes to its fallback. The CI location then goes
    /// to the build of the check worth looking at: straight there on the
    /// repository's host or one of `ciHosts`, after asking on any other host,
    /// and to `path` (the checks page) when there is no such build.
    public func resolve(for repo: Repo, ref: String? = nil, using lookup: CommitLookup, ciHosts: [String] = []) async -> Destination? {
        guard needsHeadCommit else { return url(for: repo).map(Destination.open) }
        var sha: String?
        if let ref {
            sha = try? await lookup.commit(owner: repo.owner, name: repo.name, ref: ref)
        }
        if sha == nil {
            sha = try? await lookup.commit(owner: repo.owner, name: repo.name, ref: "HEAD")
        }
        guard let sha, let page = url(for: repo, headCommit: sha) else {
            return fallbackPath.flatMap { Location(name: name, path: $0).url(for: repo) }.map(Destination.open)
        }
        guard opensBuild,
              let checks = try? await lookup.checks(owner: repo.owner, name: repo.name, commit: sha),
              let check = CICheck.preferred(checks), let link = check.link,
              let build = CICheck.buildURL(link), let host = build.host?.lowercased()
        else { return .open(page) }
        if let trusted = CICheck.openableURL(link, for: repo, ciHosts: ciHosts) {
            return .open(trusted)
        }
        return .confirm(host: host, check: check.name, build: build, otherwise: page)
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

    /// The build of the latest commit's most relevant check, from GitHub
    /// Actions or any other CI; the checks page when there's none to open.
    public static let build: Location = {
        var location = Location(name: "CI build", path: "/commit/{sha}/checks", keys: ["ci", "build", "builds"])
        location.opensBuild = true
        location.fallbackPath = "/commit/{branch}"
        return location
    }()

    /// Every status and check run reported for the latest commit on the
    /// default branch, which covers CI outside GitHub Actions too.
    public static let checks: Location = {
        var location = Location(name: "Checks", path: "/commit/{sha}/checks", keys: ["ch", "checks", "status"])
        // The commit's page shows the same checks behind its status icon.
        location.fallbackPath = "/commit/{branch}"
        return location
    }()

    public static let builtIn: [Location] = [
        code,
        local,
        Location(name: "Pull requests", path: "/pulls", keys: ["p", "pr", "prs", "pulls"]),
        Location(name: "Issues", path: "/issues", keys: ["i", "issues"]),
        build,
        checks,
        Location(name: "Actions", path: "/actions", keys: ["a", "actions"]),
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
