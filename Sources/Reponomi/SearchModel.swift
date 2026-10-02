import Combine
import Foundation
import ReponomiCore

/// State of the search panel. It has two stages: picking a repository, and —
/// after locking one with Tab — picking a location inside it.
@MainActor
final class SearchModel: ObservableObject {
    /// The location named after the space in a query such as `api pr`.
    enum InlineLocation: Equatable {
        case none
        case found(Location)
        case unknown(String)
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            message = nil
            recompute()
        }
    }
    @Published private(set) var lockedRepo: Repo?
    @Published private(set) var repoMatches: [RepoMatch] = []
    @Published private(set) var locationMatches: [Location] = []
    @Published private(set) var inlineLocation = InlineLocation.none
    @Published private(set) var selection = 0
    /// Whether ignored repositories are listed too, so they can be restored.
    @Published private(set) var showsIgnored = false
    /// A passing note for the footer, e.g. after ignoring a repository.
    @Published private(set) var message: String?
    /// Bumped whenever the search field should take keyboard focus.
    @Published private(set) var focusRequest = 0

    private let state: AppState
    private var repoQueryBeforeLock = ""
    private var selectionBeforeLock = 0
    private var subscriptions = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        // @Published fires before the new value is stored, hence the hop.
        Publishers.Merge(state.$repos.map { _ in () }, state.$config.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute(keepingSelection: true) }
            .store(in: &subscriptions)
    }

    private var rowCount: Int {
        lockedRepo == nil ? repoMatches.count : locationMatches.count
    }

    /// Returns to a blank repository search.
    func reset() {
        lockedRepo = nil
        repoQueryBeforeLock = ""
        showsIgnored = false
        query = ""
        message = nil
        recompute()
        focusRequest += 1
    }

    /// The repository the next action applies to.
    var selectedRepo: Repo? {
        lockedRepo ?? (repoMatches.indices.contains(selection) ? repoMatches[selection].repo : nil)
    }

    func toggleShowsIgnored() {
        guard lockedRepo == nil else { return }
        showsIgnored.toggle()
        recompute()
        message = showsIgnored ? "Showing ignored repositories — ⌘⌫ restores the selected one" : nil
    }

    /// Ignores the selected repository, or restores it if it is ignored.
    func toggleIgnoreSelection() {
        guard lockedRepo == nil, repoMatches.indices.contains(selection) else { return }
        let repo = repoMatches[selection].repo
        let ignore = !state.config.ignored.contains(repo.key)
        state.setIgnored(repo.key, ignore)
        recompute(keepingSelection: true)
        message = ignore ? "Ignored \(repo.fullName) — ⌘⇧. shows ignored repositories" : "Restored \(repo.fullName)"
    }

    func move(by delta: Int) {
        guard rowCount > 0 else { return }
        selection = (selection + delta + rowCount) % rowCount
    }

    func select(_ index: Int) {
        guard index >= 0, index < rowCount else { return }
        selection = index
    }

    /// Locks the selected repository and switches to choosing a location.
    func lockSelection() {
        guard lockedRepo == nil, repoMatches.indices.contains(selection) else { return }
        let parsed = ParsedQuery(query)
        repoQueryBeforeLock = parsed.repo
        selectionBeforeLock = selection
        lockedRepo = repoMatches[selection].repo
        query = parsed.location ?? ""
        recompute()
    }

    /// Steps back from the location stage. Returns false when already at the first stage.
    @discardableResult
    func unlock() -> Bool {
        guard lockedRepo != nil else { return false }
        lockedRepo = nil
        query = repoQueryBeforeLock
        recompute()
        select(selectionBeforeLock)
        return true
    }

    /// What Return would open for the current selection.
    var target: (repo: Repo, location: Location)? {
        if let lockedRepo {
            guard locationMatches.indices.contains(selection) else { return nil }
            return (lockedRepo, locationMatches[selection])
        }
        guard repoMatches.indices.contains(selection) else { return nil }
        switch inlineLocation {
        case .none: return (repoMatches[selection].repo, .code)
        case .found(let location): return (repoMatches[selection].repo, location)
        case .unknown: return nil
        }
    }

    private func recompute(keepingSelection: Bool = false) {
        let locations = state.config.locations
        if lockedRepo != nil {
            locationMatches = Location.matching(query, in: locations)
        } else {
            let parsed = ParsedQuery(query)
            let ignored = Set(state.config.ignored)
            let repos = showsIgnored || ignored.isEmpty ? state.repos : state.repos.filter { !ignored.contains($0.key) }
            repoMatches = RepoSearch.search(parsed.repo, in: repos, usage: state.usage)
            inlineLocation = parsed.location.map { text in
                Location.matching(text, in: locations).first.map(InlineLocation.found) ?? .unknown(text)
            } ?? .none
        }
        selection = keepingSelection ? min(selection, max(rowCount - 1, 0)) : 0
    }
}
