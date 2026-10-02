import Foundation

/// The search field's text split into a repository part and an optional
/// location part: `api pr` means "pull requests of the repo matching api".
public struct ParsedQuery: Equatable {
    public let repo: String
    public let location: String?

    public init(_ raw: String) {
        let text = raw.drop { $0 == " " }
        guard let space = text.firstIndex(of: " ") else {
            repo = String(text)
            location = nil
            return
        }
        repo = String(text[..<space])
        let rest = text[space...].trimmingCharacters(in: .whitespaces)
        location = rest.isEmpty ? nil : rest
    }
}

public struct UsageEntry: Codable, Equatable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int, lastUsed: Date) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public struct RepoMatch: Equatable {
    public let repo: Repo
    public let score: Double
    /// Matched character offsets into `repo.fullName`.
    public let indices: Set<Int>
}

public enum RepoSearch {
    /// Matching through the owner part ranks below matching the name alone.
    private static let ownerPenalty = 1.0
    private static let archivedPenalty = 0.5

    public static func search(
        _ query: String,
        in repos: [Repo],
        usage: [String: UsageEntry] = [:],
        now: Date = Date(),
        limit: Int = 50
    ) -> [RepoMatch] {
        let matches = repos.compactMap { repo -> RepoMatch? in
            guard let (score, indices) = match(query, repo) else { return nil }
            let adjusted = score + boost(usage[repo.fullName], now: now) - (repo.isArchived ? archivedPenalty : 0)
            return RepoMatch(repo: repo, score: adjusted, indices: indices)
        }
        return Array(matches.sorted(by: precedes).prefix(limit))
    }

    private static func match(_ query: String, _ repo: Repo) -> (Double, Set<Int>)? {
        if query.isEmpty { return (0, []) }
        if !query.contains("/"), let match = Fuzzy.match(query, in: repo.name) {
            let nameOffset = repo.fullName.count - repo.name.count
            return (match.score, Set(match.indices.map { $0 + nameOffset }))
        }
        guard let match = Fuzzy.match(query, in: repo.fullName) else { return nil }
        return (match.score - ownerPenalty, Set(match.indices))
    }

    /// Frequently and recently opened repositories float up, by at most 2.5 —
    /// roughly the worth of two or three well-placed matching characters.
    private static func boost(_ entry: UsageEntry?, now: Date) -> Double {
        guard let entry else { return 0 }
        let ageInDays = max(0, now.timeIntervalSince(entry.lastUsed)) / 86_400
        let frequency = Double(min(entry.count, 10)) / 10
        let recency = exp(-ageInDays / 14)
        return frequency + 1.5 * recency
    }

    private static func precedes(_ a: RepoMatch, _ b: RepoMatch) -> Bool {
        if a.score != b.score { return a.score > b.score }
        let aPushed = a.repo.pushedAt ?? .distantPast, bPushed = b.repo.pushedAt ?? .distantPast
        if aPushed != bPushed { return aPushed > bPushed }
        return a.repo.fullName.localizedCaseInsensitiveCompare(b.repo.fullName) == .orderedAscending
    }
}
