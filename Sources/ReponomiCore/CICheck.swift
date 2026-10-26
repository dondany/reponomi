import Foundation

/// One CI result reported for a commit: a commit status or a check run.
public struct CICheck: Equatable, Sendable {
    /// The status's context or the check run's name, e.g. `continuous-integration/jenkins/branch`.
    public var name: String
    /// Where the CI says its build is, exactly as the server sent it. Never
    /// opened unless `buildURL` allows it.
    public var link: String?

    public init(name: String, link: String? = nil) {
        self.name = name
        self.link = link
    }

    /// The check the person named. For the first of `names` that matches a
    /// linked check, ignoring case: the check with exactly that name, or else
    /// the first whose name contains it. An exact match comes first so that
    /// `build` means the `build` check, not `report-build-status`. Nil when
    /// nothing matches, so nothing is guessed.
    public static func named(_ names: [String], in checks: [CICheck]) -> CICheck? {
        let linked = checks.filter { $0.link != nil }
        for name in names where !name.isEmpty {
            if let check = linked.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
                ?? linked.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                return check
            }
        }
        return nil
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
