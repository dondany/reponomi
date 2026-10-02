import Foundation

/// A git remote URL reduced to what identifies a repository.
public struct GitRemote: Hashable {
    public let host: String
    /// `owner/name`, lowercased and without a `.git` suffix.
    public let path: String

    /// Understands `https://host/owner/name.git`, `ssh://git@host/owner/name`
    /// and the scp-like `git@host:owner/name.git`. Local paths give nil.
    public init?(_ url: String) {
        let text = url.trimmingCharacters(in: .whitespaces)
        let host: String, path: String
        if text.contains("://") {
            guard let parsed = URL(string: text), let parsedHost = parsed.host else { return nil }
            host = parsedHost
            path = parsed.path
        } else if let colon = text.firstIndex(of: ":") {
            host = String(text[..<colon].split(separator: "@").last ?? "")
            path = String(text[text.index(after: colon)...])
        } else {
            return nil
        }

        var trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        guard !host.isEmpty, !trimmed.isEmpty else { return nil }
        self.host = host.lowercased()
        self.path = trimmed
    }
}

/// The clones found in a working directory, looked up by their remotes
/// rather than their folder names, so a clone is found whatever it is called.
///
/// Whatever this returns gets opened, and tools are run inside it, on the
/// strength of the repository's name in the list. So it is strict about
/// what counts: a folder nested one level down only counts under a folder
/// named after the repository's owner, and never ahead of a clone that sits
/// directly in the working directory.
public struct LocalIndex {
    private struct Clones {
        var byRemote: [GitRemote: URL] = [:]
        var byPath: [String: URL] = [:]

        mutating func add(_ directory: URL, remotes: [GitRemote]) {
            for remote in remotes {
                if byRemote[remote] == nil { byRemote[remote] = directory }
                if byPath[remote.path] == nil { byPath[remote.path] = directory }
            }
        }

        /// A remote on the right host wins; failing that, one with the same
        /// `owner/name` counts, which covers remotes that go through an SSH
        /// host alias.
        func directory(for repo: Repo) -> URL? {
            let path = repo.fullName.lowercased()
            return byRemote[GitRemote(host: repo.host, path: path)] ?? byPath[path]
        }
    }

    /// Clones directly inside the working directory.
    private var top = Clones()
    /// Clones one level down, by the lowercased name of the folder they are in.
    private var nested: [String: Clones] = [:]

    public init() {}

    public init(scanning root: URL) {
        for directory in Self.subdirectories(of: root) {
            if let remotes = Self.remotes(ofCloneAt: directory) {
                top.add(directory, remotes: remotes)
                continue
            }
            for child in Self.subdirectories(of: directory) {
                guard let remotes = Self.remotes(ofCloneAt: child) else { continue }
                nested[directory.lastPathComponent.lowercased(), default: Clones()].add(child, remotes: remotes)
            }
        }
    }

    /// Where `repo` is cloned, if it is.
    public func directory(for repo: Repo) -> URL? {
        top.directory(for: repo) ?? nested[repo.owner.lowercased()]?.directory(for: repo)
    }

    /// The remotes of the clone at `directory`, or nil if it isn't one.
    private static func remotes(ofCloneAt directory: URL) -> [GitRemote]? {
        let config = directory.appendingPathComponent(".git/config")
        // A real config is a small regular file; don't read anything else.
        guard let values = try? config.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= 1_000_000,
              let text = try? String(contentsOf: config, encoding: .utf8)
        else { return nil }
        return remotes(inGitConfig: text)
    }

    /// The URLs of the `[remote "…"]` sections. Other sections have `url`
    /// keys too — submodules, URL rewrites — and those don't make the
    /// folder a clone of anything.
    static func remotes(inGitConfig text: String) -> [GitRemote] {
        var inRemoteSection = false
        return text.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inRemoteSection = line.lowercased().hasPrefix("[remote ")
                return nil
            }
            guard inRemoteSection else { return nil }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased() == "url" else { return nil }
            return GitRemote(parts[1])
        }
    }

    /// Real folders only: a symbolic link could lead anywhere.
    private static func subdirectories(of directory: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return (contents ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            }
            .sorted { $0.path < $1.path }
    }
}

private extension GitRemote {
    init(host: String, path: String) {
        self.host = host
        self.path = path
    }
}
