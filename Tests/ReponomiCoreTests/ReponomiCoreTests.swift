import Foundation
import Testing
@testable import ReponomiCore

@Suite struct FuzzyTests {
    @Test func rejectsNonSubsequences() {
        #expect(Fuzzy.match("xyz", in: "api-server") == nil)
        #expect(Fuzzy.match("ipa", in: "api") == nil)
        #expect(Fuzzy.match("toolong", in: "short") == nil)
    }

    @Test func emptyNeedleMatchesEverything() {
        #expect(Fuzzy.match("", in: "anything") == FuzzyMatch(score: 0, indices: []))
    }

    @Test func isCaseInsensitive() {
        #expect(Fuzzy.match("API", in: "api-server")?.indices == [0, 1, 2])
        #expect(Fuzzy.match("api", in: "API-Server")?.indices == [0, 1, 2])
    }

    @Test func exactMatchScoresHighest() throws {
        let exact = try #require(Fuzzy.match("api", in: "api"))
        let prefix = try #require(Fuzzy.match("api", in: "api-server"))
        #expect(exact.score == Fuzzy.exactScore)
        #expect(exact.score > prefix.score)
    }

    @Test func prefersPrefixThenWordStartThenScattered() throws {
        let prefix = try #require(Fuzzy.match("web", in: "web-client"))
        let wordStart = try #require(Fuzzy.match("web", in: "my-web"))
        let midWord = try #require(Fuzzy.match("web", in: "cobweb"))
        let scattered = try #require(Fuzzy.match("web", in: "wheelbase"))
        #expect(prefix.score > wordStart.score)
        #expect(wordStart.score > midWord.score)
        #expect(midWord.score > scattered.score)
    }

    @Test func picksWordStartsForInitials() {
        #expect(Fuzzy.match("ps", in: "payment-service")?.indices == [0, 8])
        #expect(Fuzzy.match("fp", in: "FastPath")?.indices == [0, 4])
    }
}

@Suite struct ParsedQueryTests {
    @Test func splitsRepoFromLocation() {
        #expect(ParsedQuery("api") == ParsedQuery("api "))
        #expect(ParsedQuery("api").location == nil)
        #expect(ParsedQuery("api pr").repo == "api")
        #expect(ParsedQuery("api pr").location == "pr")
        #expect(ParsedQuery("  api   new issue ").location == "new issue")
        #expect(ParsedQuery("").repo == "")
    }
}

@Suite struct LocationTests {
    private func best(_ query: String, in locations: [Location] = Location.builtIn) -> String? {
        Location.matching(query, in: locations).first?.name
    }

    @Test func keysSelectLocations() {
        #expect(best("p") == "Pull requests")
        #expect(best("pr") == "Pull requests")
        #expect(best("pj") == "Projects")
        #expect(best("i") == "Issues")
        #expect(best("a") == "Actions")
        #expect(best("c") == "Code")
        #expect(best("co") == "Commits")
        #expect(best("NI") == "New issue")
    }

    @Test func localFolderIsALocation() throws {
        #expect(best("l") == "Local folder")
        #expect(best("clone") == "Local folder")
        #expect(Location.matching("l", in: Location.builtIn).first?.isLocal == true)
        #expect(Location.builtIn.filter(\.isLocal).count == 1)
        // A custom location can't claim to be the local folder.
        let json = Data(#"{"name": "Mine", "path": "/x", "isLocal": true}"#.utf8)
        #expect(try JSONDecoder().decode(Location.self, from: json).isLocal == false)
    }

    @Test func fallsBackToFuzzyNames() {
        #expect(best("sett") == "Settings")
        #expect(best("wiki") == "Wiki")
        #expect(best("disc") == "Discussions")
        #expect(best("zzz") == nil)
    }

    @Test func emptyQueryListsEverythingInOrder() {
        #expect(Location.matching(" ", in: Location.builtIn) == Location.builtIn)
    }

    @Test func customLocationsOverrideBuiltInKeys() {
        var config = Config()
        config.customLocations = [Location(name: "Deployments", path: "/deployments", keys: ["d"])]
        #expect(best("d", in: config.locations) == "Deployments")
    }

    @Test func buildsURLs() {
        let repo = Repo(id: 1, name: "api", owner: "acme", defaultBranch: "trunk")
        #expect(Location.code.url(for: repo)?.absoluteString == "https://github.com/acme/api")
        #expect(Location(name: "Pulls", path: "/pulls").url(for: repo)?.absoluteString == "https://github.com/acme/api/pulls")
        #expect(Location(name: "Tree", path: "/tree/{branch}/docs").url(for: repo)?.absoluteString == "https://github.com/acme/api/tree/trunk/docs")
        for location in Location.builtIn {
            #expect(location.url(for: repo) != nil, "\(location.name) has no URL")
        }
    }

    @Test func onlyEverProducesHTTPSURLsOnTheRepositoryHost() {
        let odd = Repo(id: 1, name: "api", owner: "acme", htmlURL: "file:///Applications/Calculator.app")
        #expect(Location.code.url(for: odd) == nil)

        // A hostile default branch stays inside the path of the same host.
        let repo = Repo(id: 1, name: "api", owner: "acme", defaultBranch: "x?y#z @evil.example")
        let url = Location(name: "Tree", path: "/tree/{branch}").url(for: repo)
        #expect(url?.host == "github.com")
        #expect(url?.query == nil && url?.fragment == nil)
        #expect(url?.path == "/acme/api/tree/x?y#z @evil.example")
    }

    @Test func decodesWithoutKeys() throws {
        let json = Data(#"{"name": "Deployments", "path": "/deployments"}"#.utf8)
        #expect(try JSONDecoder().decode(Location.self, from: json).keys == [])
    }
}

@Suite struct RepoSearchTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func names(_ query: String, in repos: [Repo], usage: [String: UsageEntry] = [:]) -> [String] {
        RepoSearch.search(query, in: repos, usage: usage, now: now).map(\.repo.fullName)
    }

    @Test func ranksBetterNameMatchesFirst() {
        let repos = [
            Repo(id: 1, name: "cobweb", owner: "acme"),
            Repo(id: 2, name: "my-web", owner: "acme"),
            Repo(id: 3, name: "web", owner: "acme"),
            Repo(id: 4, name: "web-client", owner: "acme"),
            Repo(id: 5, name: "unrelated", owner: "acme"),
        ]
        #expect(names("web", in: repos) == ["acme/web", "acme/web-client", "acme/my-web", "acme/cobweb"])
    }

    @Test func nameMatchesBeatOwnerMatches() {
        let repos = [
            Repo(id: 1, name: "tools", owner: "api-team"),
            Repo(id: 2, name: "api", owner: "acme"),
        ]
        #expect(names("api", in: repos) == ["acme/api", "api-team/tools"])
    }

    @Test func slashSearchesOwnerAndName() {
        let repos = [
            Repo(id: 1, name: "api", owner: "acme"),
            Repo(id: 2, name: "api", owner: "other"),
        ]
        #expect(names("oth/api", in: repos) == ["other/api"])
    }

    @Test func highlightIndicesAreRelativeToFullName() {
        let match = RepoSearch.search("api", in: [Repo(id: 1, name: "api-server", owner: "acme")]).first
        #expect(match?.indices == [5, 6, 7])
    }

    @Test func usageLiftsRepositories() {
        let repos = [
            Repo(id: 1, name: "web-client", owner: "acme"),
            Repo(id: 2, name: "web-server", owner: "acme"),
        ]
        #expect(names("web", in: repos) == ["acme/web-client", "acme/web-server"])
        let usage = ["acme/web-server": UsageEntry(count: 3, lastUsed: now.addingTimeInterval(-3600))]
        #expect(names("web", in: repos, usage: usage) == ["acme/web-server", "acme/web-client"])
    }

    @Test func emptyQueryListsUsedThenRecentlyPushed() {
        let repos = [
            Repo(id: 1, name: "old", owner: "acme", pushedAt: now.addingTimeInterval(-90 * 86_400)),
            Repo(id: 2, name: "fresh", owner: "acme", pushedAt: now.addingTimeInterval(-3600)),
            Repo(id: 3, name: "favourite", owner: "acme", pushedAt: now.addingTimeInterval(-400 * 86_400)),
        ]
        let usage = ["acme/favourite": UsageEntry(count: 1, lastUsed: now.addingTimeInterval(-86_400))]
        #expect(names("", in: repos, usage: usage) == ["acme/favourite", "acme/fresh", "acme/old"])
    }

    @Test func respectsLimit() {
        let repos = (0..<80).map { Repo(id: $0, name: "repo-\($0)", owner: "acme") }
        #expect(RepoSearch.search("repo", in: repos).count == 50)
    }
}

@Suite struct ConfigTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"accounts": [{"owners": ["acme"]}]}"#.utf8))
        var expected = Config()
        expected.accounts = [Account(owners: ["acme"])]
        #expect(config == expected)
        #expect(config.accounts[0].host == "github.com")
        #expect(config.accounts[0].auth == .token)
        #expect(config.hasSources)
        #expect(!Config().hasSources)
    }

    @Test func readsConfigsFromBeforeSeveralAccounts() throws {
        let json = #"{"host": "git.example.com", "auth": "gh", "includeMyRepos": true, "includeForks": false}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.accounts == [Account(host: "git.example.com", auth: .githubCLI, includeMyRepos: true)])
        #expect(!config.includeForks)
    }

    @Test func roundTrips() throws {
        var config = Config()
        config.accounts = [
            Account(owners: ["acme"], includeMyRepos: true),
            Account(host: "git.example.com", auth: .githubCLI, owners: ["platform"], workingDirectory: "~/work", cloneProtocol: .https),
        ]
        config.ignored = ["github.com/acme/legacy"]
        config.localApp = "/Applications/Visual Studio Code.app"
        config.localCommand = "lazygit"
        config.customLocations = [Location(name: "Deployments", path: "/deployments", keys: ["d"])]
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func accountsKnowWhereAndHowToClone() {
        let publicRepo = Repo(id: 1, name: "api", owner: "acme")
        let internalRepo = Repo(id: 2, name: "billing", owner: "platform", htmlURL: "https://git.example.com/platform/billing")
        var config = Config()
        config.accounts = [
            Account(workingDirectory: "~/work/public"),
            Account(host: "git.example.com", workingDirectory: " ", cloneProtocol: .https),
        ]

        #expect(config.account(for: publicRepo)?.cloneURL(for: publicRepo) == "git@github.com:acme/api.git")
        #expect(config.account(for: internalRepo)?.cloneURL(for: internalRepo) == "https://git.example.com/platform/billing.git")
        #expect(config.account(for: publicRepo)?.workingDirectoryURL?.path == NSHomeDirectory() + "/work/public")
        #expect(config.account(for: internalRepo)?.workingDirectoryURL == nil)
        #expect(config.account(for: Repo(id: 3, name: "x", owner: "y", htmlURL: "https://elsewhere.example/y/x")) == nil)
        #expect(internalRepo.key == "git.example.com/platform/billing")
    }

    @Test func spansHostsOnlyWhenSeveralAccountsListRepositories() {
        var config = Config()
        config.accounts = [Account(owners: ["acme"]), Account(host: "git.example.com")]
        #expect(!config.spansHosts)
        config.accounts[1].includeMyRepos = true
        #expect(config.spansHosts)
    }

    @Test func mergeKeepsRepositoriesOfHostsThatFailed() {
        let publicRepo = Repo(id: 1, name: "web", owner: "acme")
        let goneRepo = Repo(id: 2, name: "deleted", owner: "acme")
        // Same numeric id as a github.com repository: ids are only unique per host.
        let internalRepo = Repo(id: 1, name: "billing", owner: "platform", htmlURL: "https://git.example.com/platform/billing")
        let config = Config()

        let merged = config.merge(fetched: [publicRepo], previous: [publicRepo, goneRepo, internalRepo], failedHosts: ["git.example.com"])
        #expect(merged == [publicRepo, internalRepo])
        #expect(config.merge(fetched: [publicRepo], previous: [goneRepo, internalRepo], failedHosts: []) == [publicRepo])
    }

    @Test func mergeAppliesFilters() {
        let archived = Repo(id: 1, name: "old", owner: "acme", isArchived: true)
        let fork = Repo(id: 2, name: "fork", owner: "acme", isFork: true)
        let plain = Repo(id: 3, name: "web", owner: "acme")
        var config = Config()
        #expect(config.merge(fetched: [archived, fork, plain, plain], previous: [], failedHosts: []) == [fork, plain])
        config.includeArchived = true
        config.includeForks = false
        #expect(config.merge(fetched: [archived, fork, plain], previous: [], failedHosts: []) == [archived, plain])
    }

    @Test func parsesOwners() {
        #expect(Config.parseOwners("acme, @someone  other-org,acme,,") == ["acme", "someone", "other-org"])
        #expect(Config.parseOwners("  ") == [])
    }

    @Test func normalizesHosts() {
        #expect(Config.normalizeHost("") == "github.com")
        #expect(Config.normalizeHost("https://GitHub.example.com/") == "github.example.com")
        #expect(Config.normalizeHost(" github.com ") == "github.com")
    }
}

@Suite struct LocalIndexTests {
    @Test func parsesRemoteURLs() {
        let expected = GitRemote("https://github.com/acme/api")
        #expect(expected?.host == "github.com")
        #expect(expected?.path == "acme/api")
        #expect(GitRemote("git@github.com:Acme/API.git") == expected)
        #expect(GitRemote("https://github.com/acme/api.git") == expected)
        #expect(GitRemote("https://someone@github.com/acme/api/") == expected)
        #expect(GitRemote("ssh://git@github.com:22/acme/api.git") == expected)
        #expect(GitRemote("git@work-alias:acme/api.git")?.host == "work-alias")
        #expect(GitRemote("/Users/someone/repos/api.git") == nil)
        #expect(GitRemote("file:///Users/someone/repos/api.git") == nil)
    }

    @Test func readsRemotesFromGitConfig() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "origin"]
        \turl = git@github.com:acme/api.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [remote "upstream"]
        \turl = https://github.com/upstream/api.git
        \tpushurl = no_push
        """
        #expect(LocalIndex.remotes(inGitConfig: config) == [GitRemote("git@github.com:acme/api"), GitRemote("https://github.com/upstream/api")])
    }

    /// Creates `root/<path>/.git/config` pointing at `remote`.
    private func makeClone(_ path: String, remote: String, in root: URL) throws {
        let git = root.appendingPathComponent(path).appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try Data("[remote \"origin\"]\n\turl = \(remote)\n".utf8).write(to: git.appendingPathComponent("config"))
    }

    @Test func findsClonesByRemoteWhateverTheFolderIsCalled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeClone("api", remote: "git@github.com:acme/api.git", in: root)
        try makeClone("renamed-checkout", remote: "https://github.com/acme/web.git", in: root)
        try makeClone("platform/billing", remote: "git@work-alias:platform/billing.git", in: root)
        try makeClone("too/deep/nested", remote: "git@github.com:acme/nested.git", in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not-a-repo"), withIntermediateDirectories: true)

        let index = LocalIndex(scanning: root)
        func folder(_ repo: Repo) -> String? { index.directory(for: repo)?.lastPathComponent }
        #expect(folder(Repo(id: 1, name: "api", owner: "acme")) == "api")
        #expect(folder(Repo(id: 2, name: "Web", owner: "Acme")) == "renamed-checkout")
        // Reached through an SSH alias, so only the owner/name can match.
        #expect(folder(Repo(id: 3, name: "billing", owner: "platform", htmlURL: "https://git.example.com/platform/billing")) == "billing")
        #expect(folder(Repo(id: 4, name: "nested", owner: "acme")) == nil)
        #expect(folder(Repo(id: 5, name: "api", owner: "someone-else")) == nil)
        #expect(LocalIndex(scanning: root.appendingPathComponent("missing")).directory(for: Repo(id: 1, name: "api", owner: "acme")) == nil)
    }

    /// A repository's submodules are listed in its .git/config too; that
    /// doesn't make it a clone of them.
    @Test func submoduleURLsDoNotCount() {
        let config = """
        [remote "origin"]
        \turl = git@github.com:acme/app.git
        [submodule "vendor/lib"]
        \turl = https://github.com/acme/lib.git
        [url "git@github.com:"]
        \tinsteadOf = https://github.com/
        """
        #expect(LocalIndex.remotes(inGitConfig: config) == [GitRemote("git@github.com:acme/app")])
    }

    /// Someone unpacks an archive into the working directory; inside is a
    /// folder made to look like a clone of a repository they trust.
    @Test func plantedFoldersDoNotPassForClones() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeClone("aaa-unpacked-archive/payload", remote: "git@github.com:acme/api.git", in: root)
        let repo = Repo(id: 1, name: "api", owner: "acme")

        // Nested folders only count under a folder named after the owner.
        #expect(LocalIndex(scanning: root).directory(for: repo) == nil)

        // And never ahead of a clone sitting directly in the working directory.
        try makeClone("acme/api", remote: "git@github.com:acme/api.git", in: root)
        try makeClone("zzz-real", remote: "git@github.com:acme/api.git", in: root)
        #expect(LocalIndex(scanning: root).directory(for: repo)?.lastPathComponent == "zzz-real")
    }

    @Test func prefersTheCloneOnTheRightHost() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeClone("a-public", remote: "git@github.com:acme/api.git", in: root)
        try makeClone("b-internal", remote: "git@git.example.com:acme/api.git", in: root)

        let index = LocalIndex(scanning: root)
        let internalRepo = Repo(id: 1, name: "api", owner: "acme", htmlURL: "https://git.example.com/acme/api")
        #expect(index.directory(for: internalRepo)?.lastPathComponent == "b-internal")
        #expect(index.directory(for: Repo(id: 1, name: "api", owner: "acme"))?.lastPathComponent == "a-public")
    }
}

@Suite struct GitTests {
    @Test func clonesAndReportsFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("origin.git")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        let initialize = try Process.run(URL(fileURLWithPath: "/usr/bin/git"), arguments: ["init", "--quiet", "--bare", origin.path])
        initialize.waitUntilExit()

        // The parent folder doesn't exist yet; cloning creates it.
        let destination = root.appendingPathComponent("work/checkout")
        try Git.clone(origin.path, into: destination)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git/config").path))

        #expect(throws: GitError.self) {
            try Git.clone(root.appendingPathComponent("missing.git").path, into: root.appendingPathComponent("work/other"))
        }

        // Something that looks like an option is still treated as a repository:
        // git complains about it by name instead of acting on it. (The rest
        // of git's message follows the system language.)
        do {
            try Git.clone("--upload-pack=touch \(root.path)/injected", into: root.appendingPathComponent("work/third"))
            Issue.record("cloning an option should fail")
        } catch {
            #expect(error.localizedDescription.contains("--upload-pack"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("work/other").path))
    }
}

@Suite struct TerminalTests {
    @Test func recognizesTerminalApps() {
        #expect(TerminalApp(appPath: "/System/Applications/Utilities/Terminal.app") == .terminal)
        #expect(TerminalApp(appPath: "/System/Library/CoreServices/Finder.app") == nil)
        #expect(TerminalApp(appPath: "/nonexistent/Some.app") == nil)
    }

    /// Typed into a terminal, Ctrl-C abandons the quoted path and whatever
    /// follows becomes a command of its own.
    @Test func refusesFoldersWithControlCharacters() {
        let directory = URL(fileURLWithPath: "/tmp/x\u{03}; touch /tmp/owned; echo '")
        #expect(throws: TerminalError.self) {
            try TerminalCommand.run("true", in: directory, using: .iTerm, at: "/Applications/iTerm.app")
        }
        #expect(throws: TerminalError.self) {
            try TerminalCommand.run("true", in: directory, using: .terminal, at: "/System/Applications/Utilities/Terminal.app")
        }
    }

    @Test func quotesTheFolderInTheTypedLine() {
        let directory = URL(fileURLWithPath: "/Users/me/my work/it's here")
        #expect(TerminalCommand.line(directory: directory, command: "lazygit") == #" cd -- '/Users/me/my work/it'\''s here' && lazygit"#)
    }

    @Test func scriptRunsTheCommandInTheFolderThenLeavesAShell() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("my work/it's here")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("open.command")
        try Data(TerminalCommand.script(directory: directory, command: #"basename "$PWD" > ran-in"#).utf8).write(to: script)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        // Stands in for the shell that is left open afterwards.
        process.environment = ["SHELL": "/usr/bin/true", "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: directory.appendingPathComponent("ran-in"), encoding: .utf8) == "it's here\n")
        #expect(!FileManager.default.fileExists(atPath: script.path), "the script should delete itself")
    }
}

@Suite struct GitHubCLITests {
    /// A directory holding a stand-in `gh` that is logged in to github.com only.
    private func makeFakeCLI() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reponomi-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        if [ "$*" = "auth token --hostname github.com" ]; then
          echo "gho_fake"
        else
          echo "no oauth token found" >&2
          exit 1
        fi
        """
        let executable = directory.appendingPathComponent("gh")
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return directory
    }

    @Test func locatesTheFirstExecutable() throws {
        let directory = try makeFakeCLI()
        defer { try? FileManager.default.removeItem(at: directory) }
        let found = GitHubCLI.locate(in: ["", "/nonexistent/bin", directory.path])
        #expect(found?.path == directory.appendingPathComponent("gh").path)
        #expect(GitHubCLI.locate(in: ["/nonexistent/bin"]) == nil)
    }

    @Test func skipsRelativeSearchDirectories() throws {
        let directory = try makeFakeCLI()
        defer { try? FileManager.default.removeItem(at: directory) }
        let previous = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }
        FileManager.default.changeCurrentDirectoryPath(directory.path)
        #expect(GitHubCLI.locate(in: [".", ""]) == nil)
    }

    @Test func ignoresFilesThatAreNotExecutable() throws {
        let directory = try makeFakeCLI()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("gh").path
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable)
        #expect(GitHubCLI.locate(in: [directory.path]) == nil)
    }

    @Test func readsTheTokenOfALoggedInHost() throws {
        let directory = try makeFakeCLI()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = try #require(GitHubCLI.locate(in: [directory.path]))
        #expect(try cli.token(for: "github.com") == "gho_fake")
        #expect(throws: GitHubCLIError.notLoggedIn(host: "git.example.com")) {
            try cli.token(for: "git.example.com")
        }
    }
}

@Suite struct GitHubClientTests {
    @Test func findsNextPageLink() {
        let header = #"<https://api.github.com/orgs/acme/repos?page=1>; rel="prev", <https://api.github.com/orgs/acme/repos?page=3>; rel="next", <https://api.github.com/orgs/acme/repos?page=9>; rel="last""#
        #expect(GitHubClient.nextLink(header)?.absoluteString == "https://api.github.com/orgs/acme/repos?page=3")
        #expect(GitHubClient.nextLink(#"<https://api.github.com/x?page=1>; rel="first""#) == nil)
    }

    @Test func usesEnterpriseAPIPath() {
        #expect(GitHubClient(host: "github.com").apiBase == "https://api.github.com")
        #expect(GitHubClient(host: "git.example.com").apiBase == "https://git.example.com/api/v3")
        #expect(GitHubClient(host: "acme.ghe.com").apiBase == "https://api.acme.ghe.com")
    }

    @Test func fetchesFromAnEnterpriseServer() async throws {
        let page1 = #"[{"id": 1, "name": "billing", "owner": {"login": "platform"}, "html_url": "https://git.example.com/platform/billing", "private": true}]"#
        let page2 = #"[{"id": 2, "name": "ledger", "owner": {"login": "platform"}, "html_url": "https://git.example.com/platform/ledger", "private": true}]"#
        let first = "https://git.example.com/api/v3/orgs/platform/repos?per_page=100&type=all"
        let second = "https://git.example.com/api/v3/organizations/7/repos?page=2"
        StubProtocol.responses = [
            first: (200, ["Link": "<\(second)>; rel=\"next\""], page1),
            second: (200, [:], page2),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = GitHubClient(host: "git.example.com", token: "secret", session: URLSession(configuration: configuration))

        let repos = try await client.repos(owner: "platform")
        #expect(repos.map(\.fullName) == ["platform/billing", "platform/ledger"])
        #expect(repos.map(\.host) == ["git.example.com", "git.example.com"])
        #expect(StubProtocol.authorizations == ["Bearer secret", "Bearer secret"])

        // Neither an organization nor a user by that name.
        await #expect(throws: GitHubError.unknownOwner("nobody")) {
            try await client.repos(owner: "nobody")
        }
    }

    /// A hostile or compromised server controls every field of its responses.
    @Test func doesNotTrustWhatTheServerSaysAboutURLsAndNames() throws {
        func entry(owner: String, name: String, url: String) -> String {
            #"{"id": 1, "name": "\#(name)", "owner": {"login": "\#(owner)"}, "html_url": "\#(url)", "private": false}"#
        }
        let json = "[" + [
            // Opening this would hand an arbitrary URL to the system.
            entry(owner: "acme", name: "api", url: "file:///Applications/Calculator.app"),
            // Looks internal, points somewhere else.
            entry(owner: "acme", name: "billing", url: "https://evil.example/attacker/billing"),
            // Would be cloned outside the working directory.
            entry(owner: "acme", name: "../../Library/LaunchAgents/x", url: "https://git.example.com/acme/x"),
            entry(owner: "acme", name: "..", url: "https://git.example.com/acme/.."),
            entry(owner: "ac/me", name: "web", url: "https://git.example.com/acme/web"),
            entry(owner: "acme", name: "", url: "https://git.example.com/acme/"),
        ].joined(separator: ",") + "]"

        let repos = try GitHubClient(host: "git.example.com").decodeRepos(Data(json.utf8))
        #expect(repos.map(\.htmlURL) == ["https://git.example.com/acme/api", "https://git.example.com/acme/billing"])
        #expect(repos.allSatisfy { $0.host == "git.example.com" })
    }

    @Test func refusesHostsThatAreMoreThanAHostname() async {
        for host in ["github.com@evil.example", "evil.example#.github.com", "git.example.com:8443", "git example.com", "-x.example.com", "", "a..b"] {
            #expect(!Config.isValidHost(host), "\(host) should be refused")
            await #expect(throws: GitHubError.invalidHost(host)) {
                try await GitHubClient(host: host, token: "secret").repos(owner: "acme")
            }
        }
        for host in ["github.com", "git.example.com", "acme.ghe.com", "ghe-01.corp.example"] {
            #expect(Config.isValidHost(host))
        }
    }

    @Test func refusesMalformedTokensAndOwners() async {
        await #expect(throws: GitHubError.malformedToken) {
            try await GitHubClient(host: "git.example.com", token: "abc\r\nX-Injected: 1").repos(owner: "acme")
        }
        await #expect(throws: GitHubError.unknownOwner("../../user")) {
            try await GitHubClient(host: "git.example.com", token: "secret").repos(owner: "../../user")
        }
    }

    @Test func sanitizesFreeTextFromTheServer() throws {
        let json = #"[{"id": 1, "name": "api", "owner": {"login": "acme"}, "private": false, "description": "safe\u202Eevil\u0007 text", "default_branch": "main\u0003"}]"#
        let repo = try #require(try GitHubClient().decodeRepos(Data(json.utf8)).first)
        #expect(repo.description == "safeevil text")
        #expect(repo.defaultBranch == "main")
        #expect(GitHubClient.displayable(String(repeating: "x", count: 5000)).count == 400)
    }

    @Test func cachedRepositoriesMustBeWellFormed() {
        #expect(Repo(id: 1, name: "api", owner: "acme").isWellFormed)
        #expect(Repo(id: 1, name: "api", owner: "acme", htmlURL: "https://git.example.com/acme/api").isWellFormed)
        #expect(!Repo(id: 1, name: "api", owner: "acme", htmlURL: "file:///Applications/Calculator.app").isWellFormed)
        #expect(!Repo(id: 1, name: "api", owner: "acme", htmlURL: "https://github.com/other/thing").isWellFormed)
        #expect(!Repo(id: 1, name: "../x", owner: "acme").isWellFormed)
        #expect(!Repo(id: 1, name: "api", owner: "acme", htmlURL: "http://github.com/acme/api").isWellFormed)
    }

    @Test func followsPaginationOnlyOnTheSameHostOverHTTPS() {
        let client = GitHubClient(host: "git.example.com")
        func next(_ url: String) -> URL? { client.nextPage(#"<\#(url)>; rel="next""#) }
        #expect(next("https://git.example.com/api/v3/organizations/7/repos?page=2") != nil)
        #expect(next("https://evil.example/collect?page=2") == nil)
        #expect(next("http://git.example.com/api/v3/organizations/7/repos?page=2") == nil)
        #expect(GitHubClient(host: "github.com").nextPage(#"<https://api.github.com/x?page=2>; rel="next""#) != nil)
    }

    @Test func decodesRepositories() throws {
        let json = """
        [{
          "id": 42, "name": "api", "full_name": "acme/api",
          "owner": {"login": "acme", "id": 1},
          "html_url": "https://github.com/acme/api",
          "description": null, "private": true, "fork": false, "archived": true,
          "pushed_at": "2026-09-30T12:00:00Z", "default_branch": "main"
        }]
        """
        let repo = try #require(try GitHubClient().decodeRepos(Data(json.utf8)).first)
        #expect(repo.id == 42)
        #expect(repo.fullName == "acme/api")
        #expect(repo.htmlURL == "https://github.com/acme/api")
        #expect(repo.isPrivate && repo.isArchived && !repo.isFork)
        #expect(repo.defaultBranch == "main")
        #expect(repo.pushedAt == ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z"))
    }
}

/// Serves canned responses by URL; anything else is a 404.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (status: Int, headers: [String: String], body: String)] = [:]
    nonisolated(unsafe) static var authorizations: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let stub = Self.responses[url.absoluteString]
        if stub != nil, let authorization = request.value(forHTTPHeaderField: "Authorization") {
            Self.authorizations.append(authorization)
        }
        let response = HTTPURLResponse(url: url, statusCode: stub?.status ?? 404, httpVersion: "HTTP/1.1", headerFields: stub?.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((stub?.body ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
