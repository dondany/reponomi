import Foundation

/// One CI result reported for a commit: a commit status or a check run.
public struct CICheck: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case failed, running, other
    }

    public var name: String
    public var state: State
    /// Where the CI says its build is, exactly as the server sent it. Never
    /// opened unless `mayOpen` allows it.
    public var link: String?

    public init(name: String, state: State, link: String? = nil) {
        self.name = name
        self.state = state
        self.link = link
    }

    /// The check worth looking at: the first failed one, else the first still
    /// running, else the first. Checks without a link don't count.
    public static func preferred(_ checks: [CICheck]) -> CICheck? {
        let linked = checks.filter { $0.link != nil }
        return linked.first { $0.state == .failed } ?? linked.first { $0.state == .running } ?? linked.first
    }

    /// `link` as a web address that could be opened at all: HTTPS, a plain
    /// hostname, no user name or password. Anything else is never opened or
    /// offered.
    public static func buildURL(_ link: String) -> URL? {
        guard let url = URL(string: link),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), Config.isValidHost(host)
        else { return nil }
        return url
    }

    /// `link` as a URL the app may open without asking: a `buildURL` on the
    /// repository's own host or one of `ciHosts`. Anyone who can post a
    /// status on the repository chooses the link, so other hosts need the
    /// person's say-so first.
    public static func openableURL(_ link: String, for repo: Repo, ciHosts: [String]) -> URL? {
        guard repo.isWellFormed, let url = buildURL(link), let host = url.host?.lowercased(),
              host == repo.host || ciHosts.contains(where: { $0.lowercased() == host })
        else { return nil }
        return url
    }
}

/// What a location that depends on the latest commit asks GitHub.
public protocol CommitLookup: Sendable {
    /// The latest commit on branch `ref` (`HEAD` for the default branch), as a hash.
    func commit(owner: String, name: String, ref: String) async throws -> String
    /// The statuses and check runs reported for `commit`.
    func checks(owner: String, name: String, commit: String) async throws -> [CICheck]
}

/// Where a location goes once its commit has been looked up.
public enum Destination: Equatable, Sendable {
    case open(URL)
    /// A build link on a host that isn't in `ciHosts` yet: ask before
    /// opening `build`, and open `otherwise` (the checks page) if the answer is no.
    case confirm(host: String, check: String, build: URL, otherwise: URL)
}
