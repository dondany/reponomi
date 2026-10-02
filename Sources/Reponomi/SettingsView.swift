import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import ReponomiCore

struct SettingsView: View {
    @ObservedObject var state: AppState

    @State private var accounts: [AccountDraft] = []
    @State private var includeArchived = false
    @State private var includeForks = true
    @State private var refreshMinutes = 60
    @State private var localApp: String?
    @State private var localCommand = ""
    /// Why the form could not be saved, if it couldn't.
    @State private var problem: String?
    @State private var showsIgnored = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach($accounts) { $account in
                    AccountSection(account: $account, onRemove: accounts.count > 1 ? { remove(account.id) } : nil)
                }

                Section {
                    Button("Add Another Account") { accounts.append(AccountDraft()) }
                } footer: {
                    Text("Add an account for each GitHub host you use, such as github.com and your company’s GitHub Enterprise. Their repositories are searched together.")
                        .footnote()
                }

                Section("List") {
                    Toggle("Include archived repositories", isOn: $includeArchived)
                    Toggle("Include forks", isOn: $includeForks)
                    Picker("Refresh", selection: $refreshMinutes) {
                        Text("Every 15 minutes").tag(15)
                        Text("Every hour").tag(60)
                        Text("Every 6 hours").tag(360)
                        Text("Once a day").tag(1440)
                    }
                    LabeledContent("Ignored repositories") {
                        HStack(spacing: 8) {
                            Text(state.config.ignored.isEmpty ? "None" : "\(state.config.ignored.count)")
                                .foregroundStyle(.secondary)
                            Button("Manage…") { showsIgnored = true }
                        }
                    }
                }

                Section {
                    OpenWithPicker(appPath: $localApp)
                    if localApp.flatMap(TerminalApp.init(appPath:)) != nil {
                        TextField("Run command", text: $localCommand, prompt: Text("lazygit"))
                    }
                } header: {
                    Text("Local folders")
                } footer: {
                    Text("⇧↩ in the search panel opens a repository’s clone with this app, cloning it into its account’s working directory first if needed. Terminal and iTerm can also run a command in the folder, such as `lazygit`.")
                        .footnote()
                }

                Section("Shortcut") {
                    LabeledContent("Open Reponomi") {
                        HotkeyRecorder(current: state.config.hotkey) { hotkey in
                            var config = state.config
                            config.hotkey = hotkey
                            state.update(config)
                        }
                    }
                    if !state.hotkeyRegistered {
                        Text("macOS refused this shortcut — another app may be using it. Pick a different one.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    if let launchError {
                        Text(launchError).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(spacing: 10) {
                if state.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(problem == nil && state.errors.isEmpty ? Color.secondary : Color.orange)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Save & Refresh", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540, height: 680)
        .onAppear(perform: load)
        .sheet(isPresented: $showsIgnored) {
            IgnoredRepositoriesView(state: state)
        }
    }

    private var status: String {
        if let problem { return problem }
        if !state.errors.isEmpty { return state.errors.joined(separator: "\n") }
        return state.isRefreshing ? "Refreshing…" : state.summary ?? ""
    }

    private func load() {
        let config = state.config
        accounts = config.accounts.isEmpty ? [AccountDraft()] : config.accounts.map(AccountDraft.init)
        includeArchived = config.includeArchived
        includeForks = config.includeForks
        refreshMinutes = config.refreshMinutes
        localApp = config.localApp
        localCommand = config.localCommand ?? ""
    }

    private func remove(_ id: AccountDraft.ID) {
        accounts.removeAll { $0.id == id }
    }

    private func save() {
        let saved = accounts.map(\.account)
        let hosts = saved.map(\.host)
        if let invalid = hosts.first(where: { !Config.isValidHost($0) }) {
            problem = "“\(invalid)” isn’t a valid hostname. Enter just the host, such as github.com or git.example.com."
            return
        }
        if let repeated = hosts.first(where: { host in hosts.filter { $0 == host }.count > 1 }) {
            problem = "Two accounts use \(repeated). Each account needs its own host."
            return
        }
        problem = nil

        // A saved token is left alone while its account uses the GitHub CLI,
        // so switching back doesn't mean pasting it again. It is removed
        // along with its account.
        for (draft, account) in zip(accounts, saved) where draft.auth == .token && draft.tokenLoaded {
            Keychain.setToken(draft.token.trimmingCharacters(in: .whitespacesAndNewlines), for: account.host)
        }
        for host in state.config.accounts.map(\.host) where !hosts.contains(host) {
            Keychain.setToken("", for: host)
        }

        var config = state.config
        config.accounts = saved
        config.includeArchived = includeArchived
        config.includeForks = includeForks
        config.refreshMinutes = refreshMinutes
        config.localApp = localApp
        let command = localCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        config.localCommand = command.isEmpty ? nil : command
        state.update(config)
        for index in accounts.indices {
            accounts[index].settle(as: saved[index])
        }
        Task { await state.refresh() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Could not change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// An account as it is being edited in the form.
private struct AccountDraft: Identifiable {
    let id = UUID()
    /// The host this account was last saved under, which is where its token is kept.
    var savedHost: String?
    var host = ""
    var auth = AuthMethod.token
    var token = ""
    /// Whether `token` reflects the keychain yet; see `AccountSection.loadTokenIfNeeded`.
    var tokenLoaded = false
    var owners = ""
    var includeMyRepos = false
    var workingDirectory = ""
    var cloneProtocol = CloneProtocol.ssh

    /// A new account, with no saved token to load.
    init() {
        tokenLoaded = true
    }

    init(_ account: Account) {
        savedHost = account.host
        host = account.host
        auth = account.auth
        owners = account.owners.joined(separator: ", ")
        includeMyRepos = account.includeMyRepos
        workingDirectory = account.workingDirectory ?? ""
        cloneProtocol = account.cloneProtocol
    }

    var account: Account {
        let directory = workingDirectory.trimmingCharacters(in: .whitespaces)
        return Account(
            host: Config.normalizeHost(host),
            auth: auth,
            owners: Config.parseOwners(owners),
            includeMyRepos: includeMyRepos,
            workingDirectory: directory.isEmpty ? nil : directory,
            cloneProtocol: cloneProtocol
        )
    }

    /// Shows the fields the way they were saved.
    mutating func settle(as account: Account) {
        savedHost = account.host
        host = account.host
        owners = account.owners.joined(separator: ", ")
    }
}

private struct AccountSection: View {
    @Binding var account: AccountDraft
    /// Nil when this is the only account.
    let onRemove: (() -> Void)?

    @State private var cliStatus = CLIStatus.checking

    var body: some View {
        Section {
            TextField("Host", text: $account.host, prompt: Text("github.com"))
                .onAppear(perform: loadTokenIfNeeded)
            Picker("Sign in with", selection: $account.auth) {
                Text("Access token").tag(AuthMethod.token)
                Text("GitHub CLI").tag(AuthMethod.githubCLI)
            }
            .pickerStyle(.segmented)
            .onChange(of: account.auth) { loadTokenIfNeeded() }
            .task(id: cliProbe) { await probeCLI() }
            switch account.auth {
            case .token:
                SecureField("Access token", text: $account.token)
            case .githubCLI:
                CLIStatusRow(status: cliStatus)
            }
            TextField("Organizations or users", text: $account.owners, prompt: Text("my-org, another-org"))
            Toggle("Include every repository I can access", isOn: $account.includeMyRepos)
            LabeledContent("Working directory") {
                HStack(spacing: 6) {
                    TextField("Working directory", text: $account.workingDirectory, prompt: Text("None"))
                        .labelsHidden()
                    Button("Choose…", action: chooseWorkingDirectory)
                }
            }
            if !account.workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
                Picker("Clone with", selection: $account.cloneProtocol) {
                    Text("SSH").tag(CloneProtocol.ssh)
                    Text("HTTPS").tag(CloneProtocol.https)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if let onRemove {
                    Button("Remove", action: onRemove)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        } footer: {
            Text(authHelp).footnote()
        }
    }

    private var title: String {
        account.host.trimmingCharacters(in: .whitespaces).isEmpty ? "New account" : Config.normalizeHost(account.host)
    }

    private var authHelp: LocalizedStringKey {
        switch account.auth {
        case .token:
            return "Use a classic token with the `repo` scope, or a fine-grained one with read access to Metadata. It is stored in your keychain. Public repositories on github.com can be listed without one."
        case .githubCLI:
            return "Uses the account the GitHub CLI is logged in with on this host, by running `gh auth token`. Reponomi stores no token of its own."
        }
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Repositories of \(title) are cloned into this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        account.workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Reads the saved token only once the token field is shown, so people
    /// using the GitHub CLI are never asked for keychain access.
    private func loadTokenIfNeeded() {
        guard account.auth == .token, !account.tokenLoaded else { return }
        account.token = account.savedHost.flatMap(Keychain.token(for:)) ?? ""
        account.tokenLoaded = true
    }

    /// Changes whenever the GitHub CLI's status needs checking again.
    private var cliProbe: String {
        account.auth == .githubCLI ? Config.normalizeHost(account.host) : ""
    }

    private func probeCLI() async {
        guard account.auth == .githubCLI else { return }
        let host = Config.normalizeHost(account.host)
        cliStatus = .checking
        // The host is edited a keystroke at a time; wait for it to settle.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }

        let status = await Task.detached { () -> CLIStatus in
            guard let cli = GitHubCLI.locate() else {
                return .failed(GitHubCLIError.notInstalled.localizedDescription)
            }
            do {
                _ = try cli.token(for: host)
                return .ready("Logged in to \(host), using \(cli.path)")
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        cliStatus = status
    }
}

/// The repositories hidden from the search, each with a way back.
private struct IgnoredRepositoriesView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ignored Repositories").font(.headline)
                Text("These are hidden from the search. In the search panel, ⌘⌫ ignores the selected repository; ⌘⇧. shows ignored ones, where ⌘⌫ restores them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.config.ignored.count > 8 {
                TextField("Filter", text: $filter, prompt: Text("Filter"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            List(visible, id: \.self) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name(of: key))
                        Text(host(of: key)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { state.setIgnored(key, false) }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if visible.isEmpty {
                    Text(state.config.ignored.isEmpty ? "No ignored repositories" : "No matches")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Restore All") {
                    state.config.ignored.forEach { state.setIgnored($0, false) }
                }
                .disabled(state.config.ignored.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 400)
    }

    private var visible: [String] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = state.config.ignored.sorted()
        return query.isEmpty ? sorted : sorted.filter { $0.contains(query) }
    }

    /// A key is `host/owner/name`.
    private func name(of key: String) -> String {
        key.split(separator: "/", maxSplits: 1).last.map(String.init) ?? key
    }

    private func host(of key: String) -> String {
        key.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
    }
}

/// Chooses the app that clones are opened with; nil stands for Finder.
private struct OpenWithPicker: View {
    @Binding var appPath: String?

    private static let finder = ""
    private static let other = "other"
    private let installed = LocalWorkspace.installedApps.map(\.path)

    var body: some View {
        Picker("Open with", selection: selection) {
            Text("Finder").tag(Self.finder)
            ForEach(choices, id: \.self) { path in
                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).tag(path)
            }
            Divider()
            Text("Other…").tag(Self.other)
        }
    }

    /// The apps found on this Mac, plus the chosen one if it isn't among them.
    private var choices: [String] {
        guard let appPath, !installed.contains(appPath) else { return installed }
        return installed + [appPath]
    }

    private var selection: Binding<String> {
        Binding {
            appPath ?? Self.finder
        } set: { choice in
            if choice == Self.other {
                // Let the menu close before a dialog opens over it.
                DispatchQueue.main.async(execute: chooseApp)
            } else {
                appPath = choice.isEmpty ? nil : choice
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appPath = url.path
    }
}

private extension Text {
    /// The small explanatory text under a form section.
    func footnote() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }
}

private enum CLIStatus: Equatable {
    case checking
    case ready(String)
    case failed(String)
}

private struct CLIStatusRow: View {
    let status: CLIStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch status {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking the GitHub CLI…").foregroundStyle(.secondary)
            case .ready(let message):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(message)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A button that captures the next key combination pressed.
private struct HotkeyRecorder: View {
    let current: HotkeySpec
    let onChange: (HotkeySpec) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button(monitor == nil ? current.display : "Press a shortcut…") {
            if monitor == nil { start() } else { stop() }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // escape cancels
                stop()
            } else if let hotkey = HotkeySpec(event: event) {
                onChange(hotkey)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
