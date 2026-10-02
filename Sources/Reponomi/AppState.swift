import Combine
import Foundation
import ReponomiCore

/// Settings, the repository list and how it was last refreshed.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var repos: [Repo] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    /// One message per source that failed during the last refresh.
    @Published private(set) var errors: [String] = []
    /// False when the system refused the configured global shortcut.
    @Published var hotkeyRegistered = true

    private(set) var usage: [String: UsageEntry]
    private var lastAttempt: Date?
    private var refreshQueued = false

    private struct Cache: Codable {
        var fetchedAt: Date
        var repos: [Repo]
    }

    init() {
        config = JSONFile.load(Config.self, from: AppPaths.config) ?? Config()
        usage = JSONFile.load([String: UsageEntry].self, from: AppPaths.usage) ?? [:]
        if let cache = JSONFile.load(Cache.self, from: AppPaths.cache) {
            // The cache is a file on disk; hold it to the same standard as a
            // fresh response before anything in it can be opened or cloned.
            repos = cache.repos.filter(\.isWellFormed)
            lastRefresh = cache.fetchedAt
        }
    }

    /// E.g. "76 repositories · updated 5 minutes ago"; nil before the first successful refresh.
    var summary: String? {
        guard let lastRefresh else { return nil }
        // The interface is English-only, so don't let the date follow the system language.
        let updated = lastRefresh.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US")))
        return "\(repos.count) \(repos.count == 1 ? "repository" : "repositories") · updated \(updated)"
    }

    func update(_ newConfig: Config) {
        guard newConfig != config else { return }
        config = newConfig
        JSONFile.save(newConfig, to: AppPaths.config)
    }

    /// Hides a repository (by its `Repo.key`) from the search, or brings it back.
    func setIgnored(_ key: String, _ ignored: Bool) {
        var config = self.config
        config.ignored.removeAll { $0 == key }
        if ignored { config.ignored.append(key) }
        update(config)
    }

    func recordUse(of repo: Repo) {
        usage[repo.fullName] = UsageEntry(count: (usage[repo.fullName]?.count ?? 0) + 1, lastUsed: Date())
        JSONFile.save(usage, to: AppPaths.usage)
    }

    func refreshIfStale() {
        let last = lastAttempt ?? lastRefresh ?? .distantPast
        guard Date().timeIntervalSince(last) > Double(config.refreshMinutes) * 60 else { return }
        Task { await refresh() }
    }

    /// Fetches the repository list. A call made while one is already running
    /// queues a single follow-up run, so a settings change is never missed.
    func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        repeat {
            refreshQueued = false
            await fetch()
        } while refreshQueued
        isRefreshing = false
    }

    private func fetch() async {
        let config = self.config
        lastAttempt = Date()
        let accounts = config.accounts.filter(\.hasSources)
        guard !accounts.isEmpty else {
            repos = []
            errors = []
            return
        }

        var fetched: [Repo] = []
        var failures: [String] = []
        var failedHosts = Set<String>()
        await withTaskGroup(of: (host: String, repos: [Repo], failures: [String]).self) { group in
            for account in accounts {
                group.addTask {
                    let (repos, failures) = await Self.load(account)
                    return (account.host, repos, failures)
                }
            }
            for await result in group {
                fetched += result.repos
                guard !result.failures.isEmpty else { continue }
                failedHosts.insert(result.host)
                failures += result.failures.map { config.spansHosts ? "\(result.host) — \($0)" : $0 }
            }
        }

        repos = config.merge(fetched: fetched, previous: repos, failedHosts: failedHosts)
        errors = failures.sorted()

        if failures.isEmpty || !fetched.isEmpty {
            let now = Date()
            lastRefresh = now
            JSONFile.save(Cache(fetchedAt: now, repos: repos), to: AppPaths.cache)
        }
    }

    /// Everything one account lists, plus a message per source that failed.
    private nonisolated static func load(_ account: Account) async -> (repos: [Repo], failures: [String]) {
        guard Config.isValidHost(account.host) else {
            return ([], [GitHubError.invalidHost(account.host).localizedDescription])
        }
        let token: String?
        do {
            token = try Credentials.token(for: account)
        } catch {
            return ([], [error.localizedDescription])
        }
        let client = GitHubClient(host: account.host, token: token)
        var repos: [Repo] = []
        var failures: [String] = []

        await withTaskGroup(of: (source: String, result: Result<[Repo], Error>).self) { group in
            for owner in account.owners {
                group.addTask { (owner, await capture { try await client.repos(owner: owner) }) }
            }
            if account.includeMyRepos {
                group.addTask { ("Your repositories", await capture { try await client.myRepos() }) }
            }
            for await (source, result) in group {
                switch result {
                case .success(let found): repos += found
                case .failure(let error): failures.append("\(source): \(error.localizedDescription)")
                }
            }
        }
        return (repos, failures)
    }

    private nonisolated static func capture(_ body: () async throws -> [Repo]) async -> Result<[Repo], Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }
}
