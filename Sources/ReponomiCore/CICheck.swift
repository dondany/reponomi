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

    /// `link` as a URL the app may open: HTTPS, no user name or password, and
    /// on the repository's own host or one of `ciHosts`. Anyone who can post
    /// a status on the repository chooses the link, so it can't be trusted
    /// to point anywhere else.
    public static func openableURL(_ link: String, for repo: Repo, ciHosts: [String]) -> URL? {
        guard repo.isWellFormed,
              let url = URL(string: link),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), Config.isValidHost(host),
              host == repo.host || ciHosts.contains(where: { $0.lowercased() == host })
        else { return nil }
        return url
    }
}

/// What a location that depends on the latest commit asks GitHub.
public protocol CommitLookup: Sendable {
    /// The latest commit on the default branch, as a hash.
    func headCommit(owner: String, name: String) async throws -> String
    /// The statuses and check runs reported for `commit`.
    func checks(owner: String, name: String, commit: String) async throws -> [CICheck]
}
