import AppKit
import SwiftUI
import ReponomiCore

/// Borderless floating panel that takes keyboard focus without activating
/// the app, so the previously active app stays frontmost behind it.
final class SearchPanel: NSPanel {
    static let size = NSSize(width: 680, height: 420)
    static let cornerRadius: CGFloat = 14

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?

    private enum Action {
        case browser, copyURL, local
    }

    private let state: AppState
    private let workspace: LocalWorkspace
    private let model: SearchModel
    private let panel = SearchPanel()
    private var keyMonitor: Any?

    init(state: AppState, workspace: LocalWorkspace) {
        self.state = state
        self.workspace = workspace
        self.model = SearchModel(state: state)
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: SearchPanel.cornerRadius)

        let content = NSHostingView(rootView: SearchView(model: model, state: state, workspace: workspace) { [weak self] index in
            self?.model.select(index)
            self?.activate(.browser)
        })
        content.sizingOptions = []
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        background.addSubview(content)

        panel.contentView = background
        panel.delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        model.reset()
        workspace.clearProblem()
        position()
        panel.makeKeyAndOrderFront(nil)
        state.refreshIfStale()
        workspace.rescan()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Centers the panel in the upper part of whichever screen has the pointer.
    private func position() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = SearchPanel.size
        panel.setFrame(NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.2 - size.height,
            width: size.width,
            height: size.height
        ), display: true)
    }

    /// Returns true when the key press was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // Leave keys alone while an input method is composing text.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case 53: // escape
            if !model.unlock() { hide() }
        case 125: // down arrow
            model.move(by: 1)
        case 126: // up arrow
            model.move(by: -1)
        case 36, 76: // return, keypad enter
            // ⌥ picks the default branch over the one checked out.
            let rest = flags.subtracting(.option)
            activate(rest == .command ? .copyURL : rest == .shift ? .local : .browser, defaultBranch: flags.contains(.option))
        case 48: // tab
            if flags == .shift { model.unlock() } else { model.lockSelection() }
        case 51 where flags == .command: // delete
            model.toggleIgnoreSelection()
        case 51 where model.query.isEmpty:
            return model.unlock()
        case 47 where flags == [.command, .shift]: // period, as in Finder's "show hidden files"
            model.toggleShowsIgnored()
        default:
            switch (flags, event.charactersIgnoringModifiers?.lowercased() ?? "") {
            case (.control, "n"), (.control, "j"): model.move(by: 1)
            case (.control, "p"), (.control, "k"): model.move(by: -1)
            case (.command, "r"): Task { await state.refresh() }
            case (.command, ","): onOpenSettings?()
            // Swallow ⌘Q so it dismisses the panel instead of quitting the app.
            case (.command, "w"), (.command, "q"): hide()
            default: return false
            }
        }
        return true
    }

    private func activate(_ action: Action, defaultBranch: Bool = false) {
        guard let target = model.target else {
            NSSound.beep()
            return
        }
        if action == .local || (action == .browser && target.location.isLocal) {
            openLocally(target.repo)
            return
        }
        if target.location.needsHeadCommit {
            // The page depends on a commit, so ask GitHub for it first. The
            // panel goes away now; the page opens when it's known.
            let (repo, location) = target
            let account = state.config.account(for: repo)
            let ciHosts = state.config.ciHosts
            let ref = defaultBranch ? nil : workspace.checkedOutRef(of: repo)
            state.recordUse(of: repo)
            hide()
            Task {
                let client = await AppState.client(for: repo, account: account)
                switch await location.resolve(for: repo, ref: ref, using: client, ciHosts: ciHosts) {
                case .open(let url):
                    deliver(url, action)
                case .confirm(let host, let check, let build, let otherwise):
                    deliver(confirm(host: host, check: check, build: build, repo: repo, action: action) ?? otherwise, action)
                case nil:
                    NSSound.beep()
                }
            }
            return
        }
        guard let url = target.location.url(for: target.repo) else {
            NSSound.beep()
            return
        }
        state.recordUse(of: target.repo)
        deliver(url, action)
        hide()
    }

    /// Asks whether build links on `host` may be opened. Returns `build` when
    /// they may (and remembers that), nil for the checks page instead.
    private func confirm(host: String, check: String, build: URL, repo: Repo, action: Action) -> URL? {
        let alert = NSAlert()
        alert.messageText = "Open links to \(host)?"
        let name = check.isEmpty ? "A check" : "The check “\(check)”"
        alert.informativeText = "\(name) on \(repo.fullName) links to its build on \(host). Reponomi only opens build links on hosts you allow. You can change this in Settings.\n\n\(build.absoluteString)"
        alert.addButton(withTitle: action == .copyURL ? "Allow and Copy" : "Allow and Open")
        alert.addButton(withTitle: "Use Checks Page").keyEquivalent = "\u{1b}"
        // The panel doesn't activate the app, so the alert has to.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        state.allowCIHost(host)
        return build
    }

    private func deliver(_ url: URL, _ action: Action) {
        if action == .copyURL {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the repository's clone. While it is being cloned the panel
    /// stays up to show progress; it can be dismissed and the clone carries on.
    private func openLocally(_ repo: Repo) {
        state.recordUse(of: repo)
        Task {
            switch await workspace.open(repo) {
            case .opened:
                hide()
            case .failed:
                NSSound.beep()
                // Bring the panel back if it was dismissed, so the reason is seen.
                if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
            }
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
