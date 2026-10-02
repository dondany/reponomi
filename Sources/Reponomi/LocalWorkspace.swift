import AppKit
import Combine
import ReponomiCore

/// The listed repositories as they exist on disk: which are cloned, opening
/// those, and cloning the ones that aren't.
@MainActor
final class LocalWorkspace: ObservableObject {
    enum Outcome {
        case opened, failed
    }

    /// Keys of the repositories that have a clone in their host's working directory.
    @Published private(set) var cloned: Set<String> = []
    /// Full names of the repositories being cloned right now.
    @Published private(set) var cloning: [String] = []
    /// Why the last attempt to open a repository locally failed.
    @Published private(set) var problem: String?

    private let state: AppState
    private var subscriptions = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        Publishers.Merge(state.$repos.map { _ in () }, state.$config.map { _ in () })
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rescan() }
            .store(in: &subscriptions)
    }

    func clearProblem() {
        problem = nil
    }

    /// Looks through the working directories again for clones.
    func rescan() {
        let repos = state.repos
        let roots = Dictionary(
            state.config.accounts.compactMap { account in account.workingDirectoryURL.map { (account.host, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        Task {
            cloned = await Task.detached {
                let indexes = roots.mapValues(LocalIndex.init(scanning:))
                return Set(repos.filter { indexes[$0.host]?.directory(for: $0) != nil }.map(\.key))
            }.value
        }
    }

    /// Opens the clone of `repo`, cloning it into its host's working
    /// directory first when there isn't one yet.
    func open(_ repo: Repo) async -> Outcome {
        problem = nil
        guard repo.isWellFormed else {
            problem = "\(repo.fullName) has an unexpected address, so it wasn’t opened."
            return .failed
        }
        guard let account = state.config.account(for: repo), let root = account.workingDirectoryURL else {
            problem = "No working directory is set for \(repo.host). Add one in Settings (⌘,)."
            return .failed
        }

        let existing = await Task.detached { LocalIndex(scanning: root).directory(for: repo) }.value
        if let existing {
            cloned.insert(repo.key)
            return await reveal(existing) ? .opened : .failed
        }

        guard !cloning.contains(repo.fullName) else {
            problem = "Already cloning \(repo.fullName)."
            return .failed
        }
        let destination = root.appendingPathComponent(repo.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            let path = (destination.path as NSString).abbreviatingWithTildeInPath
            problem = "Can’t clone \(repo.fullName): \(path) already exists and isn’t a clone of it."
            return .failed
        }

        cloning.append(repo.fullName)
        defer { cloning.removeAll { $0 == repo.fullName } }
        let url = account.cloneURL(for: repo)
        do {
            try await Task.detached { try Git.clone(url, into: destination) }.value
        } catch {
            problem = "Couldn’t clone \(repo.fullName): \(error.localizedDescription)"
            return .failed
        }
        cloned.insert(repo.key)
        return await reveal(destination) ? .opened : .failed
    }

    /// Opens `directory` the way Settings says to. Returns false, with
    /// `problem` set, when that fails.
    private func reveal(_ directory: URL) async -> Bool {
        guard let app = state.config.localApp, FileManager.default.fileExists(atPath: app) else {
            NSWorkspace.shared.open(directory)
            return true
        }
        let command = state.config.localCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty, let terminal = TerminalApp(appPath: app) else {
            NSWorkspace.shared.open(
                [directory],
                withApplicationAt: URL(fileURLWithPath: app),
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            return true
        }
        do {
            try await Task.detached { try TerminalCommand.run(command, in: directory, using: terminal, at: app) }.value
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Editors and terminals found on this Mac, offered for opening clones with.
    static var installedApps: [URL] {
        let identifiers = [
            "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.exafunction.windsurf",
            "com.google.antigravity", "com.apple.dt.Xcode", "com.sublimetext.4", "com.jetbrains.intellij",
            "com.jetbrains.goland", "com.jetbrains.pycharm", "com.jetbrains.WebStorm", "com.jetbrains.rustrover",
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        ]
        return identifiers.compactMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
    }
}
