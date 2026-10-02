import AppKit
import Combine
import SwiftUI
import ReponomiCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let hotKey = HotKey()
    private lazy var workspace = LocalWorkspace(state: state)
    private lazy var searchPanel = SearchPanelController(state: state, workspace: workspace)
    private var statusItem: NSStatusItem?
    private var openMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()

        searchPanel.onOpenSettings = { [weak self] in self?.showSettings() }
        hotKey.onPress = { [weak self] in self?.searchPanel.toggle() }
        state.$config.map(\.hotkey).removeDuplicates()
            .sink { [weak self] hotkey in self?.apply(hotkey) }
            .store(in: &subscriptions)

        Task { await state.refresh() }
        if !state.config.hasSources {
            showSettings()
        }
    }

    /// Launching the app again while it runs opens the search panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        searchPanel.show()
        return false
    }

    private func apply(_ hotkey: HotkeySpec) {
        state.hotkeyRegistered = hotKey.register(hotkey)
        openMenuItem?.title = "Open Reponomi  \(hotkey.display)"
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Reponomi")

        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Reponomi", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Repositories", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Reponomi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
        openMenuItem = open
    }

    /// Never shown — the app has no Dock icon — but it is what makes the
    /// standard editing shortcuts work in the app's text fields.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Quit Reponomi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    @objc private func togglePanel() {
        searchPanel.toggle()
    }

    @objc private func refresh() {
        Task { await state.refresh() }
    }

    @objc private func showSettings() {
        let window = settingsWindow ?? {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Reponomi Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
            return window
        }()

        // Rebuild the form on each opening so it starts from the saved settings.
        if !window.isVisible {
            window.contentViewController = NSHostingController(rootView: SettingsView(state: state))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
